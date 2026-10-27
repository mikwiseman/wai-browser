#import <Foundation/Foundation.h>
#include <sqlite3.h>
#include <CommonCrypto/CommonDigest.h>
#include <set>
#include <sys/stat.h>
#include "trust.h"
#include <arpa/inet.h>
#include <algorithm>
#include <cctype>
#include <fstream>
#include <iterator>
namespace wai {
std::string NormalizeDomain(std::string domain) {
  auto space=[](unsigned char c){return std::isspace(c);};
  domain.erase(domain.begin(),std::find_if_not(domain.begin(),domain.end(),space));
  domain.erase(std::find_if_not(domain.rbegin(),domain.rend(),space).base(),domain.end());
  if(!domain.empty()&&domain.back()=='.')domain.pop_back();
  if(domain.empty()||domain.size()>253||domain.find('.')==std::string::npos)return {};
  std::transform(domain.begin(),domain.end(),domain.begin(),[](unsigned char c){return std::tolower(c);});
  in_addr ip{};if(inet_pton(AF_INET,domain.c_str(),&ip)==1)return {};
  size_t start=0;
  while(start<domain.size()) {
    auto end=domain.find('.',start);if(end==std::string::npos)end=domain.size();
    if(end==start||end-start>63||domain[start]=='-'||domain[end-1]=='-')return {};
    for(size_t i=start;i<end;++i)if(!((domain[i]>='a'&&domain[i]<='z')||(domain[i]>='0'&&domain[i]<='9')||domain[i]=='-'))return {};
    start=end+1;
  }
  if(domain.back()=='.')return {};
  return domain;
}
Bytes ReadBytes(const std::string& path) {
  std::ifstream file(path,std::ios::binary);
  return Bytes(std::istreambuf_iterator<char>(file),{});
}
TrustConfig LoadConfig(const std::string& path) {
  NSString* filename=[NSString stringWithUTF8String:path.c_str()];
  if(![[NSFileManager defaultManager] fileExistsAtPath:filename])return {true,{"rzd.ru","tbank.ru","tbank-online.com","tinkoff.ru"}};
  NSData* data=[NSData dataWithContentsOfFile:filename];
  id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
  if(![json isKindOfClass:NSDictionary.class])return {false,{}};
  TrustConfig config{[json[@"enabled"] isEqual:@YES],{}};
  if([json[@"domains"] isKindOfClass:NSArray.class])for(id value in json[@"domains"]){
    if(![value isKindOfClass:NSString.class])continue;
    auto domain=NormalizeDomain([value UTF8String]);if(!domain.empty())config.domains.push_back(domain);
  }
  return config;
}
bool SaveConfig(const std::string& path,const TrustConfig& config) {
  NSMutableArray* domains=[NSMutableArray array];
  for(const auto& domain:config.domains)[domains addObject:[NSString stringWithUTF8String:domain.c_str()]];
  NSData* data=[NSJSONSerialization dataWithJSONObject:@{@"enabled":@(config.enabled),@"domains":domains} options:NSJSONWritingPrettyPrinted error:nil];
  return [data writeToFile:[NSString stringWithUTF8String:path.c_str()] options:NSDataWritingAtomic error:nil];
}
}

namespace wai {
namespace {
void Varint(Bytes& out,size_t value){while(value>127){out.push_back((value&127)|128);value>>=7;}out.push_back(value);}
void Field(Bytes& out,unsigned number,const Bytes& value){Varint(out,(number<<3)|2);Varint(out,value.size());out.insert(out.end(),value.begin(),value.end());}
std::string Fingerprint(const Bytes& cert){
 unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(cert.data(),static_cast<CC_LONG>(cert.size()),digest);
 const char* hex="0123456789ABCDEF";std::string value;
 for(auto byte:digest){value+=hex[byte>>4];value+=hex[byte&15];}return value;
}
Bytes Metadata(bool anchor,const std::vector<std::string>& domains){
 // Chromium 156 CertificateMetadata proto. See docs/profile-store.md.
 Bytes data;Field(data,1,{8,static_cast<uint8_t>(anchor?3:1)});
 if(anchor){
  Bytes constraints;
  for(const auto& domain:domains)Field(constraints,1,Bytes(domain.begin(),domain.end()));
  // An empty CIDR list means unrestricted IP SANs. Broadcast /32 permits no
  // usable TCP/TLS endpoint, while restricting both IPv4 and IPv6 SANs.
  Field(constraints,3,{10,4,255,255,255,255,16,32});Field(data,2,constraints);
 }
 return data;
}
}
bool SyncProfileTrust(const std::string& profile,const TrustConfig& config,const Bytes& root,const std::vector<Bytes>& intermediates){
 if(root.empty())return false;
 std::vector<std::string> domains;
 for(const auto& domain:config.domains){auto clean=NormalizeDomain(domain);if(clean.empty())return false;domains.push_back(clean);}
 NSString* folder=[NSString stringWithUTF8String:profile.c_str()];
 NSString* dataFolder=[folder stringByAppendingPathComponent:@"Default"];
 if(![[NSFileManager defaultManager] createDirectoryAtPath:dataFolder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return false;
 NSString* statePath=[folder stringByAppendingPathComponent:@"wai-managed-certificates.json"];
 std::set<std::string> owned;
 if([[NSFileManager defaultManager] fileExistsAtPath:statePath]){
  NSData* bytes=[NSData dataWithContentsOfFile:statePath];id old=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
  if(![old isKindOfClass:NSArray.class])return false;
  for(id value in old){
   if(![value isKindOfClass:NSString.class])return false;
   std::string hash=[value UTF8String];
   if(hash.size()!=64||hash.find_first_not_of("0123456789ABCDEF")!=std::string::npos)return false;
   owned.insert(hash);
  }
 }
 std::vector<Bytes> certificates{root};certificates.insert(certificates.end(),intermediates.begin(),intermediates.end());
 for(const auto& cert:certificates){if(cert.empty())return false;owned.insert(Fingerprint(cert));}
 sqlite3* db=nullptr;
 std::string path=profile+"/Default/ServerCertificate";
 if(sqlite3_open_v2(path.c_str(),&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,nullptr)!=SQLITE_OK){if(db)sqlite3_close(db);return false;}
 chmod(path.c_str(),0600);
 auto exec=[&](const char* sql){return sqlite3_exec(db,sql,nullptr,nullptr,nullptr)==SQLITE_OK;};
 auto finish=[&](bool ok){if(!ok)exec("ROLLBACK");sqlite3_close(db);return ok;};
 auto scalar=[&](const char* sql){sqlite3_stmt* q=nullptr;int value=-1;if(sqlite3_prepare_v2(db,sql,-1,&q,nullptr)==SQLITE_OK&&sqlite3_step(q)==SQLITE_ROW)value=sqlite3_column_int(q,0);sqlite3_finalize(q);return value;};
 int tables=scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table'");
 if(tables<0)return finish(false);
 if(tables>0&&(scalar("SELECT value FROM meta WHERE key='version'")!=1||scalar("SELECT value FROM meta WHERE key='last_compatible_version'")!=1))return finish(false);
 if(!exec("BEGIN IMMEDIATE"))return finish(false);
 if(!tables&&!exec("CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY,value LONGVARCHAR); INSERT INTO meta VALUES('version','1'),('last_compatible_version','1');"))return finish(false);
 if(!exec("CREATE TABLE IF NOT EXISTS certificates(sha256hash_hex TEXT PRIMARY KEY,der_cert BLOB NOT NULL,trust_settings BLOB NOT NULL)"))return finish(false);
 // Write ownership before committing, so interrupted root rotation is recoverable.
 NSMutableArray* ownership=[NSMutableArray array];for(auto& hash:owned)[ownership addObject:[NSString stringWithUTF8String:hash.c_str()]];
 NSData* state=[NSJSONSerialization dataWithJSONObject:ownership options:0 error:nil];
 if(![state writeToFile:statePath options:NSDataWritingAtomic error:nil])return finish(false);
 for(const auto& hash:owned){
  sqlite3_stmt* q=nullptr;if(sqlite3_prepare_v2(db,"DELETE FROM certificates WHERE sha256hash_hex=?",-1,&q,nullptr)!=SQLITE_OK)return finish(false);
  sqlite3_bind_text(q,1,hash.c_str(),-1,SQLITE_TRANSIENT);bool ok=sqlite3_step(q)==SQLITE_DONE;sqlite3_finalize(q);if(!ok)return finish(false);
 }
 if(config.enabled&&!domains.empty())for(size_t i=0;i<certificates.size();++i){
  const auto& cert=certificates[i];auto hash=Fingerprint(cert);auto metadata=Metadata(i==0,domains);sqlite3_stmt* q=nullptr;
  if(sqlite3_prepare_v2(db,"INSERT INTO certificates(sha256hash_hex,der_cert,trust_settings) VALUES(?,?,?)",-1,&q,nullptr)!=SQLITE_OK)return finish(false);
  sqlite3_bind_text(q,1,hash.c_str(),-1,SQLITE_TRANSIENT);sqlite3_bind_blob(q,2,cert.data(),static_cast<int>(cert.size()),SQLITE_TRANSIENT);sqlite3_bind_blob(q,3,metadata.data(),static_cast<int>(metadata.size()),SQLITE_TRANSIENT);
  bool ok=sqlite3_step(q)==SQLITE_DONE;sqlite3_finalize(q);if(!ok)return finish(false);
 }
 return finish(exec("COMMIT"));
}
}

#import <Foundation/Foundation.h>
#include "trust.h"
#include <sqlite3.h>
#include <iostream>
#include <stdexcept>
using namespace wai;
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 2;int checks=0;
 auto check=[&](bool value,const char*name){if(!value)throw std::runtime_error(name);++checks;};
 check(NormalizeDomain(" TBANK.RU. ")=="tbank.ru","DNS normalization");
 for(auto bad:{"ru","*.ru","https://tbank.ru","tbank.ru:443","tbank.ru/path","-bad.ru","a..ru","127.0.0.1"})check(NormalizeDomain(bad).empty(),bad);
 char folder[]="/tmp/wai-trust-test-XXXXXX";std::string profile=mkdtemp(folder);
 check(LoadConfig(profile+"/trust.json").domains==std::vector<std::string>({"rzd.ru","tbank.ru","tbank-online.com","tinkoff.ru"}),"default scope includes the bank's active legacy domain");
 auto root=ReadBytes(std::string(argv[1])+"/root.der"),inter=ReadBytes(std::string(argv[1])+"/intermediate.der");
 TrustConfig cfg{true,{"allowed.wai.test"}};
 check(SyncProfileTrust(profile,cfg,root,{inter}),"initialize profile store");
 sqlite3* db=nullptr;check(sqlite3_open((profile+"/Default/ServerCertificate").c_str(),&db)==SQLITE_OK,"open profile");
 auto scalar=[&](const char*sql){sqlite3_stmt* q=nullptr;sqlite3_prepare_v2(db,sql,-1,&q,nullptr);int n=sqlite3_step(q)==SQLITE_ROW?sqlite3_column_int(q,0):-1;sqlite3_finalize(q);return n;};
 check(scalar("SELECT COUNT(*) FROM certificates")==2,"root and intermediate");
 check(scalar("SELECT COUNT(*) FROM certificates WHERE substr(trust_settings,1,4)=x'0A020803'")==1,"only root trusted");
 check(scalar("SELECT COUNT(*) FROM certificates WHERE trust_settings=x'0A020801'")==1,"intermediate is not an anchor");
 check(scalar("SELECT COUNT(*) FROM certificates WHERE instr(trust_settings,cast('allowed.wai.test' AS blob))>0")==1,"DNS constraints persisted");
 check(scalar("SELECT COUNT(*) FROM certificates WHERE instr(trust_settings,x'1A080A04FFFFFFFF1020')>0")==1,"IP endpoints excluded");
 sqlite3_exec(db,"INSERT INTO certificates VALUES('unrelated',x'01',x'0A020801')",nullptr,nullptr,nullptr);
 check(SyncProfileTrust(profile,{false,{}},root,{inter}),"disable trust");
 check(scalar("SELECT COUNT(*) FROM certificates")==1,"only managed entries removed");
 check(scalar("SELECT COUNT(*) FROM certificates WHERE sha256hash_hex='unrelated'")==1,"user entries preserved");
 check(SyncProfileTrust(profile,{true,{}},root,{inter}),"empty domain list");
 check(scalar("SELECT COUNT(*) FROM certificates")==1,"empty does not mean global trust");
 sqlite3_exec(db,"UPDATE meta SET value='2' WHERE key='version'",nullptr,nullptr,nullptr);
 check(!SyncProfileTrust(profile,cfg,root,{inter}),"unknown schema rejected");
 check(scalar("SELECT COUNT(*) FROM certificates")==1,"unsupported database left intact");
 sqlite3_close(db);[[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:profile.c_str()] error:nil];
 std::cout<<checks<<" profile trust checks passed\n";
}}

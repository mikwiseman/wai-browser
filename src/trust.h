#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace wai {
using Bytes=std::vector<uint8_t>;
struct TrustConfig {bool enabled;std::vector<std::string> domains;};
std::string NormalizeDomain(std::string domain);
Bytes ReadBytes(const std::string& path);
TrustConfig LoadConfig(const std::string& path);
bool SaveConfig(const std::string& path,const TrustConfig& config);
// Only call while the profile is closed and the application's profile lock is held.
bool SyncProfileTrust(const std::string& profile,const TrustConfig& config,
                      const Bytes& root,const std::vector<Bytes>& intermediates);
}

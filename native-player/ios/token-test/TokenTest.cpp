// SPDX-License-Identifier: GPL-3.0-or-later
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <stdexcept>
#include <algorithm>
#include "Session.h"
#include "AuthChallenges.h"
#include "ShannonConnection.h"
#include "PlainConnection.h"
#include "BellLogger.h"
#include "protobuf/authentication.pb.h"
#include "pb_decode.h"
#include <nlohmann/json.hpp>
using Bytes=std::vector<uint8_t>;
static void varint(Bytes& b, uint64_t n) { do { b.push_back((n&127)|(n>=128?128:0)); n>>=7; } while(n); }
static void number(Bytes& b,unsigned field,uint64_t n) {varint(b,field<<3);varint(b,n);}
static void bytes(Bytes& b,unsigned field,const Bytes& v) {varint(b,(field<<3)|2);varint(b,v.size());b.insert(b.end(),v.begin(),v.end());}
static void text(Bytes& b,unsigned field,const std::string& s) {bytes(b,field,Bytes(s.begin(),s.end()));}
// Build this request without CSpot's fixed 512-byte auth_data buffer.
// OAuth tokens can be larger; copying them into that buffer would overflow.
static Bytes request(const std::string& username,int type,const Bytes& credential) {
 if(username.size()>29 || credential.empty() || credential.size()>16384) throw std::runtime_error("credential bounds");
 Bytes login,system,result;
 text(login,10,username);number(login,20,type);bytes(login,30,credential);
 number(system,10,5);number(system,60,3);
 text(system,90,"ipad-token-test");
 text(system,100,"772952ad9a1b4b44b3b67e78d1f00a18a075fed0");
 bytes(result,10,login);bytes(result,50,system);text(result,70,"cspot-1.1");return result;
}
class ProbeSession:public cspot::Session {
public:
 bool triggerTimeout() override {return false;}
 APWelcome login(const std::string& username,int type,const Bytes& credential) {
  auto payload=request(username,type,credential);
  shanConn->sendPacket(LOGIN_REQUEST_COMMAND,payload);
  auto packet=shanConn->recvPacket();
  if(packet.command!=AUTH_SUCCESSFUL_COMMAND) {
   std::fprintf(stderr,"TOKEN TEST: AP rejected login; command=%u\n",unsigned(packet.command));
   throw std::runtime_error("login rejected");
  }
  APWelcome welcome={};
  pb_istream_t stream=pb_istream_from_buffer(packet.data.data(),packet.data.size());
  if(!pb_decode(&stream,APWelcome_fields,&welcome)) throw std::runtime_error("AP welcome decode failed");
  if(!welcome.canonical_username[0] || !welcome.reusable_auth_credentials.size) throw std::runtime_error("missing reusable identity or credentials");
  return welcome;
 }
};
int main() {
 // Bound a stalled network experiment without changing the playback app.
 std::thread([] {std::this_thread::sleep_for(std::chrono::seconds(90));std::fprintf(stderr,"TOKEN TEST: timed out\n");std::exit(124);}).detach();
 try {
  std::string input; char c;
  while(std::cin.get(c)) {if(input.size()>=32768) throw std::runtime_error("input too large");input.push_back(c);}
  auto json=nlohmann::json::parse(input);
  auto token=json.at("access_token").get<std::string>();
  if(token.empty() || token.size()>16384) throw std::runtime_error("token bounds");
  bell::setDefaultLogger();
  std::puts("TOKEN TEST: connecting with OAuth token");std::fflush(stdout);
  ProbeSession first;first.connectWithRandomAp();
  auto welcome=first.login("",AuthenticationType_AUTHENTICATION_SPOTIFY_TOKEN,Bytes(token.begin(),token.end()));
  first.close();
  std::fill(token.begin(),token.end(),'\0');std::fill(input.begin(),input.end(),'\0');
  auto type=welcome.reusable_auth_credentials_type;
  if(type!=AuthenticationType_AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS && type!=AuthenticationType_AUTHENTICATION_STORED_FACEBOOK_CREDENTIALS)
   throw std::runtime_error("unexpected reusable credential type");
  std::puts("TOKEN TEST: OAuth AP login passed; testing reusable credentials on a new connection");std::fflush(stdout);
  ProbeSession second;second.connectWithRandomAp();
  auto repeated=second.login(welcome.canonical_username,type,Bytes(welcome.reusable_auth_credentials.bytes,welcome.reusable_auth_credentials.bytes+welcome.reusable_auth_credentials.size));
  second.close();
  if(std::string(repeated.canonical_username)!=welcome.canonical_username) throw std::runtime_error("canonical identity mismatch");
  std::puts("TOKEN TEST: PASS — OAuth login and fresh-connection reusable login; same canonical account.");
  std::puts("No credentials saved. Playback, refresh, and restart persistence are not tested.");return 0;
 } catch(...) {std::fprintf(stderr,"TOKEN TEST: FAIL — authorization, network, or decode failure; no secrets printed.\n");return 1;}
}

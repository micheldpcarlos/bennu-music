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
#include "Crypto.h"
#include "OAuthLogin.h"
#include <cstring>
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
 std::chrono::steady_clock::time_point deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
 bool triggerTimeout() override {return std::chrono::steady_clock::now() > deadline;}
 ~ProbeSession() {if (conn) conn->close();}
 APWelcome login(const std::string& username,int type,const Bytes& credential) {
  auto payload=request(username,type,credential);
  shanConn->sendPacket(LOGIN_REQUEST_COMMAND,payload);
  auto packet=shanConn->recvPacket();
  if(packet.command!=AUTH_SUCCESSFUL_COMMAND) {
   std::fprintf(stderr,"QR AUTH: AP rejected login; command=%u\n",unsigned(packet.command));
   throw std::runtime_error("login rejected");
  }
  APWelcome welcome={};
  pb_istream_t stream=pb_istream_from_buffer(packet.data.data(),packet.data.size());
  if(!pb_decode(&stream,APWelcome_fields,&welcome)) throw std::runtime_error("AP welcome decode failed");
  if(!welcome.canonical_username[0] || !welcome.reusable_auth_credentials.size) throw std::runtime_error("missing reusable identity or credentials");
  return welcome;
 }
};

int ipad_oauth_reusable_credentials(const char* input, char* output, size_t capacity) {
 if (!input || !output || capacity < 1) return 0;
 output[0]=0;
 try {
  std::string token(input);
  if(token.empty() || token.size()>16384) return 0;
  std::fprintf(stderr,"QR AUTH: trying OAuth AP login\n");
  ProbeSession first; first.connectWithRandomAp();
  auto welcome=first.login("",AuthenticationType_AUTHENTICATION_SPOTIFY_TOKEN,Bytes(token.begin(),token.end()));
  first.close();
  std::fill(token.begin(),token.end(),'\0');
  auto type=welcome.reusable_auth_credentials_type;
  if(type!=AuthenticationType_AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS && type!=AuthenticationType_AUTHENTICATION_STORED_FACEBOOK_CREDENTIALS)return 0;
  std::fprintf(stderr,"QR AUTH: OAuth accepted; checking reusable login\n");
  ProbeSession second; second.connectWithRandomAp();
  auto repeated=second.login(welcome.canonical_username,type,Bytes(welcome.reusable_auth_credentials.bytes,welcome.reusable_auth_credentials.bytes+welcome.reusable_auth_credentials.size));
  second.close();
  if(std::string(repeated.canonical_username)!=welcome.canonical_username ||
     (repeated.reusable_auth_credentials_type!=AuthenticationType_AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS &&
      repeated.reusable_auth_credentials_type!=AuthenticationType_AUTHENTICATION_STORED_FACEBOOK_CREDENTIALS))return 0;
  nlohmann::json record;
  record["username"]=repeated.canonical_username;
  record["authType"]=int(repeated.reusable_auth_credentials_type);
  record["authData"]=Crypto::base64Encode(Bytes(repeated.reusable_auth_credentials.bytes,repeated.reusable_auth_credentials.bytes+repeated.reusable_auth_credentials.size));
  auto text=record.dump();if(text.size()>=capacity)return 0;
  std::memcpy(output,text.c_str(),text.size()+1);
  std::fprintf(stderr,"QR AUTH: reusable account verified\n");return 1;
 } catch(...) {std::fprintf(stderr,"QR AUTH: AP login or network failure\n");return 0;}
}

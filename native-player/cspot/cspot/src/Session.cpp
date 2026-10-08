#include "Session.h"

#include <stdexcept>
#include <algorithm>
#include <limits.h>     // for CHAR_BIT
#include <cstdint>      // for uint8_t
#include <functional>   // for __base
#include <memory>       // for shared_ptr, unique_ptr, make_unique
#include <random>       // for default_random_engine, independent_bi...
#include <type_traits>  // for remove_extent_t
#include <utility>      // for move

#include "ApResolve.h"          // for ApResolve, cspot
#include "AuthChallenges.h"     // for AuthChallenges
#include "BellLogger.h"         // for AbstractLogger
#include "Logger.h"             // for CSPOT_LOG
#include "LoginBlob.h"          // for LoginBlob
#include "Packet.h"             // for Packet
#include "PlainConnection.h"    // for PlainConnection, timeoutCallback
#include "ShannonConnection.h"  // for ShannonConnection

#include "NanoPBHelper.h"  // for pbPutString, pbEncode, pbDecode
#include "pb_decode.h"
#include "protobuf/authentication.pb.h"

using random_bytes_engine =
    std::independent_bits_engine<std::default_random_engine, CHAR_BIT, uint8_t>;

using namespace cspot;

Session::Session() {
  this->challenges = std::make_unique<cspot::AuthChallenges>();
}

Session::~Session() {}

void Session::connect(std::unique_ptr<cspot::PlainConnection> connection) {
  this->conn = std::move(connection);
  conn->timeoutHandler = [this]() {
    return this->triggerTimeout();
  };
  auto helloPacket = this->conn->sendPrefixPacket(
      {0x00, 0x04}, this->challenges->prepareClientHello());
  auto apResponse = this->conn->recvPacket();
  CSPOT_LOG(info, "Received APHello response");

  auto solvedHello = this->challenges->solveApHello(helloPacket, apResponse);

  conn->sendPrefixPacket({}, solvedHello);
  CSPOT_LOG(debug, "Received shannon keys");

  // Generates the public and priv key
  this->shanConn = std::make_shared<ShannonConnection>();

  // Init shanno-encrypted connection
  this->shanConn->wrapConnection(this->conn, challenges->shanSendKey,
                                 challenges->shanRecvKey);
}

void Session::connectWithRandomAp() {
  auto apResolver = std::make_unique<ApResolve>("");
  auto conn = std::make_unique<cspot::PlainConnection>();
  conn->timeoutHandler = [this]() {
    return this->triggerTimeout();
  };

  auto apAddr = apResolver->fetchFirstApAddress();

  CSPOT_LOG(debug, "Connecting with AP <%s>", apAddr.c_str());
  conn->connect(apAddr);

  this->connect(std::move(conn));
}

std::vector<uint8_t> Session::authenticate(std::shared_ptr<LoginBlob> blob) {
  if (blob->authData.empty() || blob->authData.size() > 512 || blob->username.size() > 29)
    throw std::runtime_error("Invalid credential bounds");
  // save auth blob for reconnection purposes
  authBlob = blob;
  // prepare authentication request proto
  auto data = challenges->prepareAuthPacket(blob->authData, blob->authType,
                                            deviceId, blob->username);

  // Send login request
  this->shanConn->sendPacket(LOGIN_REQUEST_COMMAND, data);

  auto packet = this->shanConn->recvPacket();
  switch (packet.command) {
    case AUTH_SUCCESSFUL_COMMAND: {
      APWelcome welcome{};
      pb_istream_t stream = pb_istream_from_buffer(packet.data.data(), packet.data.size());
      if (!pb_decode(&stream, APWelcome_fields, &welcome) ||
          !welcome.canonical_username[0] || !welcome.reusable_auth_credentials.size ||
          (welcome.reusable_auth_credentials_type != AuthenticationType_AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS &&
           welcome.reusable_auth_credentials_type != AuthenticationType_AUTHENTICATION_STORED_FACEBOOK_CREDENTIALS))
        throw std::runtime_error("Invalid reusable credential response");
      blob->username = welcome.canonical_username;
      blob->authType = welcome.reusable_auth_credentials_type;
      blob->authData.assign(welcome.reusable_auth_credentials.bytes,
          welcome.reusable_auth_credentials.bytes + welcome.reusable_auth_credentials.size);
      CSPOT_LOG(debug, "Authorization successful; canonical credentials updated");
      return blob->authData;
    }
    case AUTH_DECLINED_COMMAND: {
      CSPOT_LOG(error, "Authorization declined");
      break;
    }
    default:
      CSPOT_LOG(error, "Unknown auth fail code %d", packet.command);
  }

  return std::vector<uint8_t>(0);
}

void Session::interrupt() {
  if (this->conn) this->conn->interrupt();
}

void Session::close() {
  this->conn->close();
}

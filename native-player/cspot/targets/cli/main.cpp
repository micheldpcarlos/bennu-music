#include <thread>
#include <chrono>
#include <mutex>
#ifdef CSPOT_IOS_APP
#include "PlayerBridge.h"
#include "auth/AuthStore.h"
#include "Catalog.h"
#include "CatalogProbe.h"
#endif
#include <functional>   // for __base, function
#include <map>          // for operator!=, map, map<>::mapped_type
#include <stdexcept>    // for invalid_argument
#include <type_traits>  // for remove_extent_t
#include <vector>       // for vector
#include <iostream>
#include <fstream>
#include <sstream> // for std::osstringstream
#include <algorithm>
#include <cstdio>

#include "BellHTTPServer.h"       // for BellHTTPServer
#include "BellLogger.h"           // for setDefaultLogger, AbstractLogger
#include "CSpotContext.h"         // for Context, Context::ConfigState
#include "CliPlayer.h"            // for CliPlayer
#include "MDNSService.h"          // for MDNSService
#include "SpircHandler.h"         // for SpircHandler
#include "WrappedSemaphore.h"     // for WrappedSemaphore
#include "civetweb.h"             // for mg_header, mg_get_request_info
#include "nlohmann/json.hpp"      // for basic_json<>::object_t, basic_json
#include "nlohmann/json_fwd.hpp"  // for json
#ifdef _WIN32
#include <winsock2.h>
#endif
#include <iostream>  // for operator<<, cout, ostream, basic_o...
#include <memory>    // for shared_ptr, make_shared, unique_ptr
#include <string>    // for string, char_traits, operator<

#include "CommandLineArguments.h"  // for CommandLineArguments
#include "Logger.h"                // for CSPOT_LOG
#include "LoginBlob.h"             // for LoginBlob

#if defined(CSPOT_ENABLE_ALSA_SINK)
#include "ALSAAudioSink.h"
#elif defined(CSPOT_ENABLE_IOS_SINK)
#include "IOSAudioQueueSink.h"
#elif defined(CSPOT_ENABLE_PORTAUDIO_SINK)
#include "PortAudioSink.h"
#else
#include "NamedPipeAudioSink.h"  // for NamedPipeAudioSink
#endif

class ZeroconfAuthenticator {
 public:
  ZeroconfAuthenticator(){};
  ~ZeroconfAuthenticator(){ stop(); };

  // Authenticator state
  int serverPort = 7864;

  // Use bell's HTTP server to handle the authentication, although anything can be used
  std::unique_ptr<bell::BellHTTPServer> server;
  std::unique_ptr<bell::MDNSService> mdns;
  std::shared_ptr<cspot::LoginBlob> blob;
  bool active() { return server != nullptr; }
  // Stop advertising on the network and close the pairing endpoint.
  void stop() {
    if (mdns) { mdns->unregisterService(); mdns.reset(); }
    server.reset();
  }

  std::mutex pairingMutex;
  bool pairingComplete = false;
  std::function<void()> onAuthSuccess;
  std::function<void()> onClose;

  void registerHandlers() {
    if (server) return;
    pairingComplete = false;
    this->server = std::make_unique<bell::BellHTTPServer>(serverPort);

    server->registerGet("/spotify_info", [this](struct mg_connection* conn) {
      std::lock_guard<std::mutex> lock(pairingMutex);
      return this->server->makeJsonResponse(this->blob->buildZeroconfInfo());
    });

    server->registerGet("/close", [this](struct mg_connection* conn) {
      this->onClose();
      return this->server->makeEmptyResponse();
    });

    server->registerPost("/spotify_info", [this](struct mg_connection* conn) {
      nlohmann::json obj;
      // Prepare a success response for spotify
      obj["status"] = 101;
      obj["spotifyError"] = 0;
      obj["statusString"] = "ERROR-OK";

      std::string body = "";
      auto requestInfo = mg_get_request_info(conn);
      if (requestInfo->content_length > 0) {
        body.resize(requestInfo->content_length);
        mg_read(conn, &body[0], requestInfo->content_length);

        mg_header hd[10];
        int num = mg_split_form_urlencoded(&body[0], hd, 10);
        std::map<std::string, std::string> queryMap;

        // Parse the form data
        for (int i = 0; i < num; i++) {
          queryMap[hd[i].name] = hd[i].value;
        }

        CSPOT_LOG(info, "Received zeroauth POST data");

        std::lock_guard<std::mutex> lock(pairingMutex);
        if (pairingComplete) return server->makeJsonResponse(obj.dump());
        // Pass user's credentials to the blob
        blob->loadZeroconfQuery(queryMap);

        // We have the blob, proceed to login
        onAuthSuccess();
        pairingComplete = true;
      }

      return server->makeJsonResponse(obj.dump());
    });

    // Register mdns service, for spotify to find us
    mdns = MDNSService::registerService(
        blob->getDeviceName(), "_spotify-connect", "_tcp", "", serverPort,
        {{"VERSION", "1.0"}, {"CPath", "/spotify_info"}, {"Stack", "SP"}});
    std::cout << "Waiting for spotify app to connect..." << std::endl;
  }
};

int main(int argc, char** argv) {
#ifdef _WIN32
  WSADATA wsaData;
  WORD wVersionRequested = MAKEWORD(2, 2);
  int WSerr = WSAStartup(wVersionRequested, &wsaData);
  if (WSerr != 0)
    exit(1);
#endif
  bell::setDefaultLogger();
  bell::enableTimestampLogging();
#ifdef CSPOT_ENABLE_ALSA_SINK
  auto audioSink = std::make_unique<ALSAAudioSink>();
#elif defined(CSPOT_ENABLE_IOS_SINK)
  std::unique_ptr<AudioSink> audioSink = std::make_unique<IOSAudioQueueSink>();
#elif defined(CSPOT_ENABLE_PORTAUDIO_SINK)
  std::unique_ptr<AudioSink> audioSink = std::make_unique<PortAudioSink>();
#else
  auto audioSink = std::make_unique<NamedPipeAudioSink>();
#endif

  if (!audioSink->setParams(44100, 2, 16)) {
    std::cerr << "Audio output initialization failed" << std::endl;
    return 1;
  }

  // Semaphore, main thread waits for this to be signaled before signing in
  auto loggedInSemaphore = std::make_shared<bell::WrappedSemaphore>(1);

  auto zeroconfServer = std::make_unique<ZeroconfAuthenticator>();
  std::atomic<bool> isRunning{true};

  zeroconfServer->onClose = [&isRunning]() {
    isRunning = false;
  };

  try {
    auto args = CommandLineArguments::parse(argc, argv);
    if (args->shouldShowHelp) {
      std::cout << "Usage: cspotcli [OPTION]...\n";
      std::cout << "Emulate a Spotify connect speaker.\n";
      std::cout << "\n";
      std::cout << "Run without any arguments to authenticate by using mDNS on "
                   "the local network (open the spotify app and CSpot should "
                   "appear as a device on the local network). \n";
      std::cout << "Alternatively you can specify a username and password to "
                   "login with.";
      std::cout << "\n";
      std::cout << "-u, --username            your spotify username\n";
      std::cout << "-p, --password            your spotify password, note that "
                   "if you use facebook login you can set a password in your "
                   "account settings\n";
      std::cout << "-c, --credentials         json file to store/load reusable credentials\n";
      std::cout << "-b, --bitrate             bitrate (320, 160, 96)\n";
      std::cout << "\n";
      std::cout << "ddd 2022\n";
      return 0;
    }

    // Name shown in the Spotify app's device list (mDNS, zeroconf and Spirc all use it).
    // The device id is derived from this name, so renaming registers a new Connect device.
    static const char* const kDeviceName = "Bennu Music";
    auto loginBlob = std::make_shared<cspot::LoginBlob>(kDeviceName);

#ifdef CSPOT_IOS_APP
    // No saved account: listen for a Spotify Connect pairing from the phone AND poll the Keychain
    // (filled by the QR sign-in screen). Whichever happens first logs the player in.
    std::atomic<bool> pairedFromPhone{false};
    {
      char savedCredentials[4096] = {};
      int savedAccount = ipad_auth_load(savedCredentials, sizeof(savedCredentials));
      if (savedAccount < 0) throw std::runtime_error("Account storage failed. Check AUTH log status.");
      if (savedAccount > 0) {
        loginBlob->loadJson(savedCredentials);
        std::fill(savedCredentials, savedCredentials + sizeof(savedCredentials), '\0');
        loggedInSemaphore->give();
      } else {
        std::fprintf(stderr, "AUTH: no saved account; waiting for QR sign-in or Connect pairing\n");
        zeroconfServer->blob = std::make_shared<cspot::LoginBlob>(kDeviceName);
        auto* server = zeroconfServer.get();
        zeroconfServer->onAuthSuccess = [loginBlob, server, &pairedFromPhone]() {
          // Copy before signaling; HTTP discovery uses its own blob, never the live engine blob.
          loginBlob->loadJson(server->blob->toJson());
          pairedFromPhone = true;
        };
        auto* zeroconf = zeroconfServer.get();
        ipad_player::setDiscoverableHandler([zeroconf](bool on) {
          if (on && !zeroconf->active()) { zeroconf->registerHandlers(); std::fprintf(stderr, "APP: visible on the network\n"); }
          else if (!on && zeroconf->active()) { zeroconf->stop(); std::fprintf(stderr, "APP: hidden from the network\n"); }
        });
        if (ipad_engine_discoverable()) zeroconfServer->registerHandlers();
        for (;;) {
          if (pairedFromPhone) { std::fprintf(stderr, "AUTH: paired from the phone\n"); break; }
          if (ipad_player::stopRequested()) break;
          int account = ipad_auth_load(savedCredentials, sizeof(savedCredentials));
          if (account < 0) throw std::runtime_error("Account storage failed. Check AUTH log status.");
          if (account > 0) {
            loginBlob->loadJson(savedCredentials);
            std::fill(savedCredentials, savedCredentials + sizeof(savedCredentials), '\0');
            std::fprintf(stderr, "AUTH: account arrived from the sign-in screen\n");
            break;
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
        if (ipad_player::stopRequested()) return 0;
        ipad_player::setDiscoverableHandler(nullptr);
        zeroconfServer->stop();
        loggedInSemaphore->give();
      }
    }
#else
    // Login using Command line arguments
    if (!args->username.empty()) {
      loginBlob->loadUserPass(args->username, args->password);
      loggedInSemaphore->give();
    }
    // reusable credentials
    else if (!args->credentials.empty()) {
        std::ifstream file(args->credentials);
        std::ostringstream credentials;
        credentials << file.rdbuf();
        loginBlob->loadJson(credentials.str());
        loggedInSemaphore->give();
    }
    // ZeroconfAuthenticator
    else {
      zeroconfServer->blob = loginBlob;
      zeroconfServer->onAuthSuccess = [loggedInSemaphore]() {
        loggedInSemaphore->give();
      };
      zeroconfServer->registerHandlers();
    }

#endif

    // Wait for authentication to complete
    loggedInSemaphore->wait();
    std::shared_ptr<cspot::Context> ctx;
    CSPOT_LOG(info, "Creating player");
#ifdef CSPOT_IOS_APP
    ipad_player_connecting();
    const int connectionAttempts = 8;  // ~2 minutes of backoff before giving up
#else
    const int connectionAttempts = 1;
#endif
    for (int attempt = 0; attempt < connectionAttempts; ++attempt) {
      // Failed pre-login sessions are discarded before retrying.
      ctx = cspot::Context::createFromBlob(loginBlob);
      if (args->setBitrate) ctx->config.audioFormat = args->bitrate;
#ifdef CSPOT_IOS_APP
      ctx->config.volume = static_cast<int>(ipad_player_saved_volume());   // reported in the device state; default was 0
#endif
      try {
        ctx->session->connectWithRandomAp();
        break;
      } catch (...) {
        ctx.reset();
        if (attempt + 1 == connectionAttempts) throw;
        int wait = std::min(30, 2 << attempt);
        std::fprintf(stderr, "AUTH: AP connection failed; retry %d/%d in %ds\n", attempt + 2, connectionAttempts, wait);
#ifdef CSPOT_IOS_APP
        for (int i = 0; i < wait * 5 && !ipad_player::stopRequested(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(200));
        if (ipad_player::stopRequested()) return 0;
#else
        std::this_thread::sleep_for(std::chrono::seconds(wait));
#endif
      }
    }
    ctx->config.authData = ctx->session->authenticate(loginBlob);
    ctx->config.username = loginBlob->username;

    // Auth successful
    if (ctx->config.authData.size() > 0) {
#ifdef CSPOT_IOS_APP
      if (!ipad_auth_save(loginBlob->toJson().c_str()))
        throw std::runtime_error("Could not save reusable credentials in Keychain.");
      std::fprintf(stderr, "AUTH: account login passed and credentials saved; ready for playback\n");
#endif
      // when credentials file is set, then store reusable credentials
      if (!args->credentials.empty()) {
          std::ofstream file(args->credentials);
          file << loginBlob->toJson();
      }

      // Start spirc task
      auto handler = std::make_shared<cspot::SpircHandler>(ctx);

      // Start handling mercury messages
      ctx->session->startTask();

      // Create a player, pass the handler
      auto player = std::make_shared<CliPlayer>(std::move(audioSink), handler);
#ifdef CSPOT_IOS_APP
      std::weak_ptr<cspot::SpircHandler> weakHandler(handler);
      ipad_player::setControlHandler([weakHandler](int command) {
        auto active = weakHandler.lock();
        if (!active) return false;
        switch (command) {
          case IPadTogglePause: {
            IPadPlayerSnapshot snapshot{};
            ipad_player_snapshot(&snapshot);
            active->setPause(!snapshot.paused);
            return true;
          }
          case IPadPrevious: return active->previousSong();
          case IPadNext: return active->nextSong();
          default: return false;
        }
      });
      auto catalog = std::make_shared<ipad_player::Catalog>(ctx);
      ipad_player::setCatalogService([catalog](const std::string& kind, const std::string& argument, const ipad_player::CatalogPublish& publish) {
        if (kind == "search") catalog->search(argument, publish);
        else if (kind == "album") catalog->album(argument, publish);
        else if (kind == "artist") catalog->artist(argument, publish);
        else if (kind == "playlist") catalog->playlist(argument, publish);
        else if (kind == "collection") catalog->collection(publish);
        else if (kind == "recent") catalog->recent(publish);
        else if (kind == "profile") catalog->profile(publish);
        else if (kind == "playlists") catalog->playlists(publish);
        else if (kind == "home") catalog->home(publish);
        else if (kind == "context") catalog->context(argument, publish);
        else if (kind == "tracks") {
          std::vector<std::string> uris; std::string current;
          for (char c : argument) { if (c == ',') { if (!current.empty()) uris.push_back(current); current.clear(); } else current += c; }
          if (!current.empty()) uris.push_back(current);
          catalog->tracks(uris, publish);
        } else throw std::invalid_argument("unknown catalog request");
      });
      ipad_player::setPlaybackHandlers(
          [weakHandler](const std::vector<std::string>& uris, size_t index, const std::string& context) {
            auto active = weakHandler.lock(); if (!active) return false;
            active->loadTracks(uris, index, context); return true;
          },
          [weakHandler](uint32_t positionMs) {
            auto active = weakHandler.lock(); if (active) active->seekTo(positionMs);
          });
      std::weak_ptr<cspot::Context> weakContext(ctx);
      // The packet loop polls every 200 ms, so clearing the flag is enough; touching the socket
      // from here raced the session's own reconnect logic.
      ipad_player::setStopHandler([&isRunning]() { isRunning = false; });
      ipad_player::setDropHandler([weakContext]() {
        if (auto context = weakContext.lock()) { try { context->session->interrupt(); } catch (...) {} }
      });
      ipad_player::setQueueHandlers(
          [weakHandler](const std::vector<std::string>& uris) { if (auto active = weakHandler.lock()) active->queueTracks(uris); },
          [weakHandler](int mode) { if (auto active = weakHandler.lock()) active->setRepeat(mode); });
      ipad_player::setVolumeHandler([weakHandler](uint32_t volume) { if (auto active = weakHandler.lock()) active->setRemoteVolume((int)volume); });
      {
        auto* zeroconf = zeroconfServer.get();
        zeroconf->blob = std::make_shared<cspot::LoginBlob>(kDeviceName);
        zeroconf->onAuthSuccess = [zeroconf]() {
          // Another phone picked this iPad: keep that account and restart the engine with it.
          std::fprintf(stderr, "AUTH: pairing from the phone while signed in; switching account\n");
          if (ipad_auth_save(zeroconf->blob->toJson().c_str())) ipad_engine_stop();
        };
        ipad_player::setDiscoverableHandler([zeroconf](bool on) {
          if (on && !zeroconf->active()) { zeroconf->registerHandlers(); std::fprintf(stderr, "APP: visible on the network\n"); }
          else if (!on && zeroconf->active()) { zeroconf->stop(); std::fprintf(stderr, "APP: hidden from the network\n"); }
        });
        if (ipad_engine_discoverable()) zeroconf->registerHandlers();
      }
      ipad_player_ready();
      ipad_player::runCatalogProbeIfRequested(ctx);
#endif

      // If we wanted to handle multiple devices, we would halt this loop
      // when a new zeroconf login is requested, and reinitialize the session
      while (isRunning) {
#ifdef CSPOT_IOS_APP
        ipad_player::dispatchPending();
        ipad_player_reconnecting(ctx->session->reconnecting() ? 1 : 0);
        try { ctx->session->handlePacket(); }
        catch (...) { if (ipad_player::stopRequested()) break; throw; }
#else
        ctx->session->handlePacket();
#endif
      }

#ifdef CSPOT_IOS_APP
      ipad_player::clearControlHandler();
      ipad_player::setDiscoverableHandler(nullptr);
      zeroconfServer->stop();
      std::fprintf(stderr, "APP: engine loop ended; disconnecting\n");
#endif
      handler->disconnect();
      player->disconnect();
#ifdef CSPOT_IOS_APP
      std::fprintf(stderr, "APP: engine disconnected\n");
#endif
    }

  } catch (std::invalid_argument e) {
    std::cout << "Invalid options passed: " << e.what() << "\n";
    std::cout << "Pass --help for more informaton. \n";
    return 1;  // we exit with an non-zero exit code
  }

  return 0;
}

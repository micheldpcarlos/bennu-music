#include <stdio.h>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <exception>

int main() {
    try {
        std::string message("C++ runtime working");
        std::vector<int> values(100, 7);
        std::mutex mutex;
        int result = 0;

        std::thread worker([&]() {
            std::lock_guard<std::mutex> lock(mutex);
            result = values.at(42);
        });
        worker.join();

        printf("%s; thread result=%d\n", message.c_str(), result);
        return result == 7 ? 0 : 1;
    } catch (const std::exception& error) {
        fprintf(stderr, "C++ error: %s\n", error.what());
        return 2;
    }
}

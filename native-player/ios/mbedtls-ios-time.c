#include <mbedtls/platform_time.h>
#include <mbedtls/platform_util.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdint.h>

static mach_timebase_info_data_t timebase;
static pthread_once_t timebase_once = PTHREAD_ONCE_INIT;

static void initialize_timebase(void)
{
    mach_timebase_info(&timebase);
}

mbedtls_ms_time_t mbedtls_ms_time(void)
{
    pthread_once(&timebase_once, initialize_timebase);

    uint64_t ticks = mach_absolute_time();
    uint64_t nanoseconds =
        (ticks / timebase.denom) * timebase.numer +
        ((ticks % timebase.denom) * timebase.numer) / timebase.denom;

    return (mbedtls_ms_time_t)(nanoseconds / 1000000);
}

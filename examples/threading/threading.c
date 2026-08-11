#include "threading.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <errno.h>

// Optional: use these functions to add debug or error prints to your application
#define DEBUG_LOG(msg,...)
// #define DEBUG_LOG(msg,...) printf("threading: " msg "\n" , ##__VA_ARGS__)
#define ERROR_LOG(msg,...) printf("threading ERROR: " msg "\n" , ##__VA_ARGS__)

static int sleep_ms(long milliseconds)
{
    struct timespec request = {
        .tv_sec  = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L
    };

    while (nanosleep(&request, &request) == -1) {
        if (errno != EINTR) {
            return -1;
        }
    }
    return 0;
}

void* threadfunc(void* thread_param)
{

    // TODO: wait, obtain mutex, wait, release mutex as described by thread_data structure
    // hint: use a cast like the one below to obtain thread arguments from your parameter
    //struct thread_data* thread_func_args = (struct thread_data *) thread_param;

    struct thread_data* thread_func_args = (struct thread_data *) thread_param;

    if (sleep_ms(thread_func_args->obtain_ms) != 0) {
        ERROR_LOG("sleep before obtaining mutex failed");
        return thread_param;                 // thread_complete_success stays false
    }

    int rc = pthread_mutex_lock(thread_func_args->mutex);
    if (rc != 0) {
        ERROR_LOG("pthread_mutex_lock failed: %s", strerror(rc));
        return thread_param;
    }

    if (sleep_ms(thread_func_args->release_ms) != 0) {
        ERROR_LOG("sleep while holding mutex failed");
        pthread_mutex_unlock(thread_func_args->mutex);   // release before bailing
        return thread_param;
    }

    rc = pthread_mutex_unlock(thread_func_args->mutex);
    if (rc != 0) {
        ERROR_LOG("pthread_mutex_unlock failed: %s", strerror(rc));
        return thread_param;
    }

    thread_func_args->thread_complete_success = true;
    return thread_param;
}


bool start_thread_obtaining_mutex(pthread_t *thread, pthread_mutex_t *mutex,int wait_to_obtain_ms, int wait_to_release_ms)
{
    /**
     * TODO: allocate memory for thread_data, setup mutex and wait arguments, pass thread_data to created thread
     * using threadfunc() as entry point.
     *
     * return true if successful.
     *
     * See implementation details in threading.h file comment block
     */

    if (thread == NULL) {
        ERROR_LOG("thread can't be NULL");
        return false;
    }
    struct thread_data * t_data = malloc(sizeof(struct thread_data));
    if (t_data == NULL) {
        ERROR_LOG("cannot allocate memory");
        return false;
    }

    t_data->obtain_ms = wait_to_obtain_ms;
    t_data->release_ms = wait_to_release_ms;
    t_data->thread_complete_success = false;
    t_data->mutex = mutex;

    int ret;
    ret = pthread_create(thread, NULL, threadfunc, t_data);
    if (ret != 0) {
        ERROR_LOG("pthread_create failed: %s", strerror(ret));
        free(t_data);
        return false;
    }

    // Note: thread_complete_success is owned by the thread (set in threadfunc);
    // the parent must not touch t_data after the thread has started.
    DEBUG_LOG("thread started");
    return true;
}


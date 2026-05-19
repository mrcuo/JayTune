/*
 * afc_write - Write a local file to iOS device via AFC protocol
 *
 * Usage: afc_write [-n] <udid> <local_path> <remote_path>
 *   -n  Use network connection (WiFi sync)
 *   Reads local_path content and writes to remote_path on device
 *
 * Compile:
 *   gcc -o afc_write afc_write.c -limobiledevice-1.0 -lplist-2.0 \
 *       -I/opt/homebrew/include -L/opt/homebrew/lib
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/lockdown.h>

#define BUF_SIZE (256 * 1024)  /* 256KB chunks */

int main(int argc, char* argv[]) {
    int arg_offset = 1;
    int use_network = 0;

    /* Parse optional -n flag */
    if (argc > 1 && strcmp(argv[1], "-n") == 0) {
        use_network = 1;
        arg_offset++;
    }

    if (argc - arg_offset < 3) {
        fprintf(stderr, "Usage: %s [-n] <udid> <local_path> <remote_path>\n", argv[0]);
        return 1;
    }

    const char* udid = argv[arg_offset];
    const char* local_path = argv[arg_offset + 1];
    const char* remote_path = argv[arg_offset + 2];

    /* Open local file for reading */
    FILE* fp = fopen(local_path, "rb");
    if (!fp) {
        fprintf(stderr, "Failed to open local file: %s\n", local_path);
        return 1;
    }

    idevice_t device = NULL;
    lockdownd_client_t client = NULL;
    afc_client_t afc = NULL;

    /* Connect to device (USB or network) */
    idevice_error_t ret;
    if (use_network) {
        ret = idevice_new_with_options(&device, udid, IDEVICE_LOOKUP_NETWORK);
    } else {
        ret = idevice_new(&device, udid);
    }
    if (ret != IDEVICE_E_SUCCESS) {
        fprintf(stderr, "idevice_new failed: %d\n", ret);
        fclose(fp);
        return 1;
    }

    /* Lockdown handshake */
    lockdownd_error_t ldret = lockdownd_client_new_with_handshake(device, &client, "jaytune_afc_write");
    if (ldret != LOCKDOWN_E_SUCCESS) {
        fprintf(stderr, "lockdownd failed: %d\n", ldret);
        fclose(fp);
        idevice_free(device);
        return 1;
    }

    /* Start AFC service */
    lockdownd_service_descriptor_t service = NULL;
    ldret = lockdownd_start_service(client, "com.apple.afc", &service);
    if (ldret != LOCKDOWN_E_SUCCESS || service == NULL) {
        fprintf(stderr, "afc service failed: %d\n", ldret);
        lockdownd_client_free(client);
        fclose(fp);
        idevice_free(device);
        return 1;
    }

    afc_error_t aret = afc_client_new(device, service, &afc);
    if (aret != AFC_E_SUCCESS) {
        fprintf(stderr, "afc_client failed: %d\n", aret);
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(client);
        fclose(fp);
        idevice_free(device);
        return 1;
    }

    /* Ensure the parent directory exists on the device */
    /* Extract parent directory from remote_path */
    char* path_copy = strdup(remote_path);
    if (path_copy) {
        char* last_slash = strrchr(path_copy, '/');
        if (last_slash && last_slash != path_copy) {
            *last_slash = '\0';
            /* Try to create the directory (ignore error if it already exists) */
            afc_make_directory(afc, path_copy);
        }
        free(path_copy);
    }

    /* Open remote file for writing */
    uint64_t handle = 0;
    aret = afc_file_open(afc, remote_path, AFC_FOPEN_WRONLY, &handle);
    if (aret != AFC_E_SUCCESS) {
        fprintf(stderr, "file_open '%s' failed: %d\n", remote_path, aret);
        afc_client_free(afc);
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(client);
        fclose(fp);
        idevice_free(device);
        return 1;
    }

    /* Read local file in chunks, write to AFC */
    char buf[BUF_SIZE];
    size_t bytes_read = 0;
    uint64_t total_written = 0;

    while ((bytes_read = fread(buf, 1, BUF_SIZE, fp)) > 0) {
        uint32_t bytes_written = 0;
        aret = afc_file_write(afc, handle, buf, (uint32_t)bytes_read, &bytes_written);
        if (aret != AFC_E_SUCCESS) {
            fprintf(stderr, "file_write failed: %d (wrote %llu bytes so far)\n", aret, (unsigned long long)total_written);
            afc_file_close(afc, handle);
            afc_client_free(afc);
            lockdownd_service_descriptor_free(service);
            lockdownd_client_free(client);
            fclose(fp);
            idevice_free(device);
            return 1;
        }
        total_written += bytes_written;
    }

    /* Close and cleanup */
    afc_file_close(afc, handle);
    afc_client_free(afc);
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(client);
    fclose(fp);
    idevice_free(device);

    /* Report success */
    printf("OK: wrote %llu bytes to %s\n", (unsigned long long)total_written, remote_path);
    fflush(stdout);

    return 0;
}

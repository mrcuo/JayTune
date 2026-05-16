/*
 * afc_read2 - Read a file from iOS device via AFC protocol
 *
 * Usage: afc_read2 [-n] <udid> <remote_path>
 *   -n  Use network connection (WiFi sync)
 *   Outputs file content to stdout (binary safe)
 *
 * Compile:
 *   gcc -o afc_read2 afc_read2.c -limobiledevice-1.0 -lplist-2.0 \
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

    if (argc - arg_offset < 2) {
        fprintf(stderr, "Usage: %s [-n] <udid> <remote_path>\n", argv[0]);
        return 1;
    }

    const char* udid = argv[arg_offset];
    const char* remote_path = argv[arg_offset + 1];

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
        return 1;
    }

    /* Lockdown handshake */
    lockdownd_error_t ldret = lockdownd_client_new_with_handshake(device, &client, "jaytune_afc_read");
    if (ldret != LOCKDOWN_E_SUCCESS) {
        fprintf(stderr, "lockdownd failed: %d\n", ldret);
        idevice_free(device);
        return 1;
    }

    /* Start AFC service */
    lockdownd_service_descriptor_t service = NULL;
    ldret = lockdownd_start_service(client, "com.apple.afc", &service);
    if (ldret != LOCKDOWN_E_SUCCESS || service == NULL) {
        fprintf(stderr, "afc service failed: %d\n", ldret);
        lockdownd_client_free(client);
        idevice_free(device);
        return 1;
    }

    afc_error_t aret = afc_client_new(device, service, &afc);
    if (aret != AFC_E_SUCCESS) {
        fprintf(stderr, "afc_client failed: %d\n", aret);
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(client);
        idevice_free(device);
        return 1;
    }

    /* Open file for reading */
    uint64_t handle = 0;
    aret = afc_file_open(afc, remote_path, AFC_FOPEN_RDONLY, &handle);
    if (aret != AFC_E_SUCCESS) {
        fprintf(stderr, "file_open '%s' failed: %d\n", remote_path, aret);
        afc_client_free(afc);
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(client);
        idevice_free(device);
        return 1;
    }

    /* Read file in chunks, write to stdout */
    char buf[BUF_SIZE];
    uint32_t bytes_read = 0;
    while (1) {
        aret = afc_file_read(afc, handle, buf, BUF_SIZE, &bytes_read);
        if (aret != AFC_E_SUCCESS || bytes_read == 0) break;
        fwrite(buf, 1, bytes_read, stdout);
    }

    /* Close and cleanup */
    afc_file_close(afc, handle);
    afc_client_free(afc);
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(client);
    idevice_free(device);

    /* Ensure stdout is flushed */
    fflush(stdout);

    return 0;
}

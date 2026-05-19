/*
 * afc_head - Read first N bytes of a file from iOS device via AFC protocol
 *
 * Usage: afc_head [-n] [-b <bytes>] <udid> <remote_path>
 *   -n           Use network connection (WiFi sync)
 *   -b <bytes>   Max bytes to read (default: 65536 = 64KB)
 *   Outputs file content to stdout (binary safe)
 *
 * This tool is optimized for metadata scanning: only reads the file header
 * so ffprobe can extract tags without transferring the entire file over WiFi.
 *
 * Compile:
 *   gcc -o afc_head afc_head.c -limobiledevice-1.0 -lplist-2.0 \
 *       -I/opt/homebrew/include -L/opt/homebrew/lib
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/lockdown.h>

#define BUF_SIZE (256 * 1024)  /* 256KB chunks */
#define DEFAULT_MAX_BYTES 65536  /* 64KB - enough for M4A/MP3 metadata */

int main(int argc, char* argv[]) {
    int arg_offset = 1;
    int use_network = 0;
    uint64_t max_bytes = DEFAULT_MAX_BYTES;

    /* Parse flags */
    while (arg_offset < argc && argv[arg_offset][0] == '-') {
        if (strcmp(argv[arg_offset], "-n") == 0) {
            use_network = 1;
            arg_offset++;
        } else if (strcmp(argv[arg_offset], "-b") == 0 && arg_offset + 1 < argc) {
            max_bytes = strtoull(argv[arg_offset + 1], NULL, 10);
            arg_offset += 2;
        } else {
            fprintf(stderr, "Usage: %s [-n] [-b <bytes>] <udid> <remote_path>\n", argv[0]);
            return 1;
        }
    }

    if (argc - arg_offset < 2) {
        fprintf(stderr, "Usage: %s [-n] [-b <bytes>] <udid> <remote_path>\n", argv[0]);
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
    lockdownd_error_t ldret = lockdownd_client_new_with_handshake(device, &client, "jaytune_afc_head");
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

    /* Read only up to max_bytes */
    char buf[BUF_SIZE];
    uint32_t bytes_read = 0;
    uint64_t total_read = 0;
    while (total_read < max_bytes) {
        uint32_t to_read = (uint32_t)((max_bytes - total_read < BUF_SIZE) ? (max_bytes - total_read) : BUF_SIZE);
        aret = afc_file_read(afc, handle, buf, to_read, &bytes_read);
        if (aret != AFC_E_SUCCESS || bytes_read == 0) break;
        fwrite(buf, 1, bytes_read, stdout);
        total_read += bytes_read;
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

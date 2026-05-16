/*
 * afc_ls - List directory contents on iOS device via AFC protocol
 *
 * Usage: afc_ls [-n] <udid> <path>
 *   -n  Use network connection (WiFi sync)
 *
 * Compile:
 *   gcc -o afc_ls afc_ls.c -limobiledevice-1.0 -lplist-2.0 \
 *       -I/opt/homebrew/include -L/opt/homebrew/lib
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/lockdown.h>

int main(int argc, char* argv[]) {
    int arg_offset = 1;
    int use_network = 0;

    /* Parse optional -n flag */
    if (argc > 1 && strcmp(argv[1], "-n") == 0) {
        use_network = 1;
        arg_offset++;
    }

    if (argc - arg_offset < 2) {
        fprintf(stderr, "Usage: %s [-n] <udid> <path>\n", argv[0]);
        return 1;
    }

    const char* udid = argv[arg_offset];
    const char* path = argv[arg_offset + 1];

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
    lockdownd_error_t ldret = lockdownd_client_new_with_handshake(device, &client, "jaytune_afc_ls");
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

    /* List directory */
    char** entries = NULL;
    aret = afc_read_directory(afc, path, &entries);
    if (aret != AFC_E_SUCCESS || entries == NULL) {
        fprintf(stderr, "read_directory failed: %d\n", aret);
        afc_client_free(afc);
        lockdownd_service_descriptor_free(service);
        lockdownd_client_free(client);
        idevice_free(device);
        return 1;
    }

    /* Print each entry (skip "." and "..") */
    for (int i = 0; entries[i] != NULL; i++) {
        if (strcmp(entries[i], ".") != 0 && strcmp(entries[i], "..") != 0) {
            printf("%s\n", entries[i]);
        }
        free(entries[i]);
    }
    free(entries);

    /* Cleanup */
    afc_client_free(afc);
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(client);
    idevice_free(device);

    return 0;
}

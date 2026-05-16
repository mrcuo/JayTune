/*
 * afc_rm - Delete a file on iOS device via AFC protocol
 *
 * Usage: afc_rm [-n] <udid> <remote_path>
 *   -n  Use network connection (WiFi sync)
 *
 * Compile:
 *   gcc -o afc_rm afc_rm.c -limobiledevice-1.0 -lplist-2.0 \
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
    lockdownd_error_t ldret = lockdownd_client_new_with_handshake(device, &client, "jaytune_afc_rm");
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

    /* Remove file/directory */
    aret = afc_remove_path(afc, remote_path);
    if (aret != AFC_E_SUCCESS) {
        /* Try as directory with contents */
        aret = afc_remove_path_and_contents(afc, remote_path);
        if (aret != AFC_E_SUCCESS) {
            fprintf(stderr, "remove '%s' failed: %d\n", remote_path, aret);
            afc_client_free(afc);
            lockdownd_service_descriptor_free(service);
            lockdownd_client_free(client);
            idevice_free(device);
            return 1;
        }
    }

    printf("OK: Removed '%s'\n", remote_path);

    /* Cleanup */
    afc_client_free(afc);
    lockdownd_service_descriptor_free(service);
    lockdownd_client_free(client);
    idevice_free(device);

    return 0;
}

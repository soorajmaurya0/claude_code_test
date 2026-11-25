LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

SRC_URI = "git://github.com/AMDESE/amd-ipmi-oem.git;branch=main;protocol=https"
SRCREV = "dce2ee2b6a2560609a64b5a385ddd42577632be9"

S = "${WORKDIR}/git"

DEPENDS = "boost libpam phosphor-dbus-interfaces phosphor-ipmi-host phosphor-logging sdbusplus"

inherit meson pkgconfig

FILES:${PN} += "${libdir}/ipmid-providers/lib*${SOLIBS}"
FILES:${PN}-dev += "${libdir}/ipmid-providers/lib*${SOLIBSDEV}"


From 0f5c173f807dbcf64e47582c4c3c5c851fbe93e8 Mon Sep 17 00:00:00 2001
From: soorajmaurya0 <soorajmaurya0@users.noreply.github.com>
Date: Wed, 25 Nov 2026 16:45:36 +0530
Subject: [PATCH] Server power operations: keep only Force off shutdown

Remove the "Reboot server" group (Graceful restart, Force restart and
the Reboot button) and the "Graceful shutdown" option from
Operations > Server power operations.

Only "Shutdown server" with "Force off" (pre-selected) and the
"Shut down" button remain. After confirmation the Shut down button
always issues ComputerSystem.Reset with ResetType "ForceOff".

The "Power on" button shown while the host is off is unchanged.
UI-only change: bmcweb still accepts the other ResetType values
over Redfish.

Upstream-Status: Inappropriate [platform-specific UI policy]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HoVXwfNMdYuscEGyrLLf4P
---
 .../ServerPowerOperations.vue                 | 101 ++----------------
 1 file changed, 8 insertions(+), 93 deletions(-)

diff --git a/src/views/Operations/ServerPowerOperations/ServerPowerOperations.vue b/src/views/Operations/ServerPowerOperations/ServerPowerOperations.vue
index 491dc7f..1c20853 100644
--- a/src/views/Operations/ServerPowerOperations/ServerPowerOperations.vue
+++ b/src/views/Operations/ServerPowerOperations/ServerPowerOperations.vue
@@ -84,60 +84,11 @@
             </b-button>
           </template>
           <template v-else>
-            <!-- Reboot server options -->
-            <b-form novalidate class="mb-5" @submit.prevent="rebootServer">
-              <b-form-group
-                :label="$t('pageServerPowerOperations.rebootServer')"
-              >
-                <b-form-radio
-                  v-model="form.rebootOption"
-                  name="reboot-option"
-                  data-test-id="serverPowerOperations-radio-rebootOrderly"
-                  value="orderly"
-                >
-                  {{ $t('pageServerPowerOperations.gracefulRestart') }}
-                  <info-tooltip
-                    :title="$t('pageServerPowerOperations.gracefulRestartInfo')"
-                  />
-                </b-form-radio>
-                <b-form-radio
-                  v-model="form.rebootOption"
-                  name="reboot-option"
-                  data-test-id="serverPowerOperations-radio-rebootImmediate"
-                  value="immediate"
-                >
-                  {{ $t('pageServerPowerOperations.forceRestart') }}
-                  <info-tooltip
-                    :title="$t('pageServerPowerOperations.forceRestartInfo')"
-                  />
-                </b-form-radio>
-              </b-form-group>
-              <b-button
-                variant="primary"
-                type="submit"
-                data-test-id="serverPowerOperations-button-reboot"
-              >
-                {{ $t('pageServerPowerOperations.reboot') }}
-              </b-button>
-            </b-form>
-            <!-- Shutdown server options -->
+            <!-- Shutdown server options (Force off only) -->
             <b-form novalidate @submit.prevent="shutdownServer">
               <b-form-group
                 :label="$t('pageServerPowerOperations.shutdownServer')"
               >
-                <b-form-radio
-                  v-model="form.shutdownOption"
-                  name="shutdown-option"
-                  data-test-id="serverPowerOperations-radio-shutdownOrderly"
-                  value="orderly"
-                >
-                  {{ $t('pageServerPowerOperations.gracefulShutdown') }}
-                  <info-tooltip
-                    :title="
-                      $t('pageServerPowerOperations.gracefulShutdownInfo')
-                    "
-                  />
-                </b-form-radio>
                 <b-form-radio
                   v-model="form.shutdownOption"
                   name="shutdown-option"
@@ -188,8 +139,7 @@ export default {
     return {
       $t: useI18n().t,
       form: {
-        rebootOption: 'orderly',
-        shutdownOption: 'orderly',
+        shutdownOption: 'immediate',
       },
     };
   },
@@ -229,33 +179,6 @@ export default {
     powerOn() {
       this.$store.dispatch('controls/serverPowerOn');
     },
-    rebootServer() {
-      const modalMessage = i18n.global.t(
-        'pageServerPowerOperations.modal.confirmRebootMessage',
-      );
-      const modalOptions = {
-        title: i18n.global.t(
-          'pageServerPowerOperations.modal.confirmRebootTitle',
-        ),
-        okTitle: i18n.global.t('global.action.confirm'),
-        cancelTitle: i18n.global.t('global.action.cancel'),
-        autoFocusButton: 'ok',
-      };
-
-      if (this.form.rebootOption === 'orderly') {
-        this.$bvModal
-          .msgBoxConfirm(modalMessage, modalOptions)
-          .then((confirmed) => {
-            if (confirmed) this.$store.dispatch('controls/serverSoftReboot');
-          });
-      } else if (this.form.rebootOption === 'immediate') {
-        this.$bvModal
-          .msgBoxConfirm(modalMessage, modalOptions)
-          .then((confirmed) => {
-            if (confirmed) this.$store.dispatch('controls/serverHardReboot');
-          });
-      }
-    },
     shutdownServer() {
       const modalMessage = i18n.global.t(
         'pageServerPowerOperations.modal.confirmShutdownMessage',
@@ -269,20 +192,12 @@ export default {
         autoFocusButton: 'ok',
       };
 
-      if (this.form.shutdownOption === 'orderly') {
-        this.$bvModal
-          .msgBoxConfirm(modalMessage, modalOptions)
-          .then((confirmed) => {
-            if (confirmed) this.$store.dispatch('controls/serverSoftPowerOff');
-          });
-      }
-      if (this.form.shutdownOption === 'immediate') {
-        this.$bvModal
-          .msgBoxConfirm(modalMessage, modalOptions)
-          .then((confirmed) => {
-            if (confirmed) this.$store.dispatch('controls/serverHardPowerOff');
-          });
-      }
+      // Only Force off (ResetType: ForceOff) is exposed in the UI.
+      this.$bvModal
+        .msgBoxConfirm(modalMessage, modalOptions)
+        .then((confirmed) => {
+          if (confirmed) this.$store.dispatch('controls/serverHardPowerOff');
+        });
     },
   },
 };
-- 
2.43.0


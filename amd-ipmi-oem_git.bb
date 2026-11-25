LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

SRC_URI = "git://github.com/AMDESE/amd-ipmi-oem.git;branch=main;protocol=https"
SRCREV = "dce2ee2b6a2560609a64b5a385ddd42577632be9"

S = "${WORKDIR}/git"

DEPENDS = "boost libpam phosphor-dbus-interfaces phosphor-ipmi-host phosphor-logging sdbusplus"

inherit meson pkgconfig

FILES:${PN} += "${libdir}/ipmid-providers/lib*${SOLIBS}"
FILES:${PN}-dev += "${libdir}/ipmid-providers/lib*${SOLIBSDEV}"

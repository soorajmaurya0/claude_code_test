#!/bin/sh
# kvm_hid_diag.sh - check the KVM keyboard/mouse path on OpenBMC 2.18 (AST2600 vhub)
#
# Run on the BMC while the KVM page is OPEN in the web UI:
# obmc-ikvm binds the HID gadget only while a VNC client is connected,
# and /dev/hidg0,1 exist only while it is bound.
#
# Usage: sh kvm_hid_diag.sh          (paste the full output back)

R=${KVM_DIAG_ROOT:-}                     # test hook only; leave unset on the BMC
SVC=obmc-ikvm.service
G=$R/sys/kernel/config/usb_gadget/obmc_hid
VHUB=$R/sys/bus/platform/devices/1e6a0000.usb-vhub
UDCC=$R/sys/class/udc
HIDC=$R/sys/class/hidg

ok()   { echo "  [ OK ] $*"; }
bad()  { echo "  [FAIL] $*"; }
note() { echo "  [ .. ] $*"; }
rd()   { cat "$1" 2>/dev/null; }

CLIENTS=0; UDC=""; STATE=""; WRT=skip; POISON=0; VHUB_OK=0; MUX=""

# ---------------------------------------------------------------- 1. service
echo "== 1. obmc-ikvm service"
if [ "$(systemctl is-active $SVC 2>/dev/null)" = active ]; then
    ok "$SVC is active"
else
    bad "$SVC is not active (2.18 name is obmc-ikvm.service, not start-ipkvm)"
fi

ARGS=$(systemctl show -p ExecStart --value $SVC 2>/dev/null |
       sed -n 's/.*argv\[\]=\([^;]*\);.*/\1/p')
KDEV=$(echo "$ARGS" | sed -n 's/.* -k[[:space:]]*\([^[:space:]]*\).*/\1/p')
PDEV=$(echo "$ARGS" | sed -n 's/.* -p[[:space:]]*\([^[:space:]]*\).*/\1/p')
UARG=$(echo "$ARGS" | sed -n 's/.* -u[[:space:]]*\([^[:space:]]*\).*/\1/p')
note "ExecStart: ${ARGS:-<unknown>}"
[ -n "$KDEV" ] || bad "no -k <keyboard> in ExecStart: keyboard events are dropped"
[ -n "$PDEV" ] || bad "no -p <mouse> in ExecStart: mouse events are dropped"
[ -n "$UARG" ] && note "UDC forced with -u $UARG (auto-search over the vhub is skipped)"

NRES=$(systemctl show -p NRestarts --value $SVC 2>/dev/null)
case "$NRES" in ''|*[!0-9]*) NRES=0 ;; esac
[ "$NRES" -gt 0 ] && bad "service restarted $NRES times this boot (crash on HID open? check: coredumpctl list)"

ERRS=$(journalctl -u $SVC -b --no-pager 2>/dev/null | grep -iE "fail|error" | tail -n 6)
if [ -n "$ERRS" ]; then
    bad "obmc-ikvm logged errors:"
    echo "$ERRS" | sed 's/^/           /'
    echo "$ERRS" | grep -qE "Failed to (connect|disconnect) HID gadget" && POISON=1
else
    note "no errors logged (note: obmc-ikvm never logs dropped ESHUTDOWN/EAGAIN writes)"
fi

NETOK=0
if command -v netstat >/dev/null 2>&1 || command -v ss >/dev/null 2>&1; then
    NETOK=1
    CLIENTS=$( (netstat -tn 2>/dev/null || ss -tn 2>/dev/null) |
               awk '$4 ~ /:5900$/ && ($6 == "ESTABLISHED" || $1 == "ESTAB")' | wc -l | tr -d ' ')
    if [ "$CLIENTS" -gt 0 ]; then
        ok "$CLIENTS KVM client(s) connected to obmc-ikvm"
    else
        bad "no KVM client connected: open the KVM page, keep it open, rerun"
    fi
else
    CLIENTS=1
    note "netstat/ss not available: cannot count KVM clients (assuming the KVM page is open)"
fi

# ---------------------------------------------------------------- 2. vhub
echo "== 2. USB virtual hub (AST2600 port A, device mode)"
if [ -d "$VHUB" ]; then
    VHUB_OK=1
    ok "vhub probed (1e6a0000.usb-vhub)"
    for p in "$VHUB"/1e6a0000.usb-vhub:p*; do
        [ -d "$p" ] || continue
        n=$(basename "$p")
        note "$n  state=$(rd "$UDCC/$n/state")  function=$(rd "$UDCC/$n/function")"
    done
else
    bad "$VHUB missing: &vhub not enabled/probed or node renamed; obmc-ikvm cannot pick a port"
fi

if [ -e "$R/sys/bus/platform/devices/1e6a1000.usb" ]; then
    bad "ehci0 (1e6a1000, port A HOST) is probed: conflicts with the vhub"
else
    ok "ehci0 (port A host) not probed"
fi

if command -v devmem >/dev/null 2>&1; then
    V=$(devmem 0x1e6e2440 2>/dev/null)
    if [ -n "$V" ]; then
        MUX=$(( (V >> 24) & 3 ))
        case "$MUX" in
            1) ok "SCU440=$V  [25:24]=01 USB2AD (port A = device)" ;;
            0) bad "SCU440=$V  [25:24]=00 USB2ADP, not USB2AD (pinctrl_usb2ad_default not applied)" ;;
            *) bad "SCU440=$V  [25:24]=$MUX = port A HOST mode (USB2AH/USB2AHP)" ;;
        esac
    fi
else
    note "devmem not available: cannot read SCU440 pinmux"
fi

# ---------------------------------------------------------------- 3. gadget
echo "== 3. HID gadget (obmc_hid)"
if [ ! -d "$G" ]; then
    bad "gadget directory missing: create_usbhid.sh never ran"
else
    UDC=$(rd "$G/UDC")
    if [ -z "$UDC" ]; then
        bad "gadget NOT bound to any UDC"
    else
        ok "bound to $UDC"
        STATE=$(rd "$UDCC/$UDC/state")
        case "$STATE" in
            configured)     ok "port state: configured (host enumerated + configured it)" ;;
            "not attached") bad "port state: not attached (host never reset this port since BMC boot)" ;;
            *)              bad "port state: '$STATE' (enumeration started but not completed)" ;;
        esac
    fi

    for f in "$G"/functions/hid.*; do
        [ -d "$f" ] || continue
        d=$(rd "$f/dev"); pr=$(rd "$f/protocol"); len=$(rd "$f/report_length")
        node=""
        for c in "$HIDC"/hidg*; do
            [ -e "$c/dev" ] && [ "$(rd "$c/dev")" = "$d" ] && node=/dev/$(basename "$c")
        done
        case "$pr" in
            1) kind=keyboard; want=8; exp=$KDEV ;;
            2) kind=mouse;    want=6; exp=$PDEV ;;
            *) kind="protocol=$pr"; want=""; exp="" ;;
        esac
        msg="$(basename "$f"): $kind  dev=$d  report_length=$len  node=${node:-none (unbound)}"
        if [ -n "$want" ] && [ "$len" != "$want" ]; then
            bad "$msg  -> report_length must be $want"
        elif [ -n "$node" ] && [ -n "$exp" ] && [ "$node" != "$exp" ]; then
            bad "$msg  -> obmc-ikvm sends $kind reports to $exp (mismatch)"
        else
            ok "$msg"
        fi
        if [ "$kind" = mouse ]; then
            H=$(od -An -tx1 "$f/report_desc" 2>/dev/null | tr -d ' \n')
            if [ -n "$H" ] && ! echo "$H" | grep -q '0509'; then
                bad "mouse report descriptor has no Button usage page (clicks can never work)"
            fi
        fi
    done
fi

# ---------------------------------------------------------------- 4. write test
echo "== 4. live write test (Left-Shift tap, harmless)"
if [ "$STATE" = configured ] && [ -n "$KDEV" ] && [ -c "$KDEV" ]; then
    if command -v timeout >/dev/null 2>&1; then
        OUT=$(timeout 2 sh -c "printf '\002\000\000\000\000\000\000\000' > $KDEV &&
                               printf '\000\000\000\000\000\000\000\000' > $KDEV" 2>&1)
        RC=$?
        if [ $RC -eq 0 ]; then
            WRT=ok;  ok "host accepted keyboard reports on $KDEV"
        elif [ $RC -eq 124 ] || [ $RC -eq 143 ]; then
            WRT=blocked; bad "write blocked >2s: host enumerated it but is not polling the HID endpoint"
        else
            WRT=error; bad "write error (rc=$RC${OUT:+, $OUT}): usually ESHUTDOWN = host has not configured the HID interface"
        fi
    else
        note "timeout command not available: skipped"
    fi
else
    note "skipped (needs state=configured and a valid -k device)"
fi

# ---------------------------------------------------------------- 5. kernel log
echo "== 5. kernel log (vhub/udc/hid)"
dmesg 2>/dev/null | grep -iE "vhub|udc|hidg|gadget|usb2a" | tail -n 8 | sed 's/^/           /'

# ---------------------------------------------------------------- verdict
echo "== VERDICT"
if [ "$NETOK" -eq 1 ] && [ "$CLIENTS" -eq 0 ] && [ -n "$UDC" ]; then
    echo "  Gadget is bound with no KVM client: it was bound by hand. obmc-ikvm's next bind"
    echo "  will fail (EBUSY) and stay failed. Fix: systemctl restart $SVC, open KVM, rerun."
elif [ "$CLIENTS" -eq 0 ] && [ -z "$UDC" ]; then
    echo "  Open the KVM page in the web UI, keep it open, and rerun this script."
elif [ "$VHUB_OK" -eq 0 ]; then
    echo "  vhub driver/device missing: fix DT (&vhub status=okay) and kernel config."
elif [ -z "$UDC" ]; then
    echo "  obmc-ikvm did not bind the gadget (see journal lines above)."
    [ "$POISON" -eq 1 ] && echo "  A failed UDC write sticks until restart: systemctl restart $SVC, reopen KVM, rerun."
    echo "  Never write the UDC file by hand while $SVC is running."
elif [ "$STATE" = "not attached" ]; then
    echo "  BMC side is fine; the HOST never sees the virtual hub. Hardware/firmware path:"
    [ -n "$MUX" ] && [ "$MUX" != 1 ] && echo "   - fix pinmux first: SCU440[25:24] must be 01 (USB2AD)"
    echo "   - AST2600 USB port A (balls A4/B4) must route via DC-SCI to a host USB port on the HPM"
    echo "     (check mux/hub/redriver enables on the HPM; port B needs a different setup)"
    echo "   - host BIOS must not disable that USB port"
    echo "   - on the host: lsusb | grep 1d6b:0107  (USB Virtual Hub) must be present"
elif [ "$STATE" != configured ]; then
    echo "  Host starts enumeration but fails: check host dmesg for 'device descriptor read'"
    echo "  errors (signal integrity, long trace, missing redriver, wrong port speed)."
elif [ "$WRT" = ok ]; then
    echo "  BMC -> host USB path works. Remaining suspects: obmc-ikvm args/session (one KVM tab only),"
    echo "  or the host input stack. On the host run: sudo evtest  (pick an 'OpenBMC Virtual"
    echo "  Keyboard and Mouse' device) while typing in the KVM window."
else
    echo "  Host enumerated the device but is not taking reports: check host dmesg for hid errors"
    echo "  and USB autosuspend; replug with: systemctl restart $SVC, then reopen KVM."
fi

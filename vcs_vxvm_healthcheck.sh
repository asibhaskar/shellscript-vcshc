#!/bin/bash
# Veritas VxVM and VCS Health Check Script
# Author: Bhaskar Reddy Asi
# Note: Run as root or a user with Veritas privileges
LOGFILE="/tmp/veritas_health_check_$(date +%F_%H%M%S).log"
echo "===== Veritas Cluster Health Check on $(hostname -s) =====" | tee -a "$LOGFILE"
echo "Date: $(date)" | tee -a "$LOGFILE"
echo "--------------------------------------------------------" | tee -a "$LOGFILE"

# 1. Ensure VxVM commands are available
if ! command -v vxdg &>/dev/null; then
    echo "Veritas Volume Manager (vxdg) command not found. Please verify VxVM is installed."
    exit 1
fi

echo "Checking Veritas Disk Group Status..."  | tee -a "$LOGFILE"
echo "--------------------------------------" | tee -a "$LOGFILE"

# 2. List all disk groups and their status
vxdg list | awk 'NR>1 {print $1}' | while read -r dgname; do
    status=$(vxdg list "$dgname" | grep -i "state" | awk '{print $2}')
    if [[ "$status" != "enabled" ]]; then
        echo "Disk Group [$dgname] is in failed or abnormal state: $status"
    else
        echo "Disk Group [$dgname] is healthy (State: $status)"
    fi
done | tee -a "$LOGFILE"

echo ""
# 3. List any deported disk groups and their status
echo "Checking for deported or unavailable disk groups..."
vxdg list | grep -i "deported"
if [[ $? -ne 0 ]]; then
    echo "No deported disk groups found."
fi | tee -a "$LOGFILE"

echo""
# 4. List any Failed disks in any groups
echo "Checking for failed disks in any disk group..."
vxdisk list | grep -i "failed"
if [[ $? -ne 0 ]]; then
    echo "No failed disks found in any group."
fi | tee -a "$LOGFILE"

echo""
# 5. VxVM Disk Group Status
echo -e "\n=== VxVM Disk Group Status ===" | tee -a "$LOGFILE"
vxdg list | tee -a "$LOGFILE"

echo""
# 6. VxVM Disks Status
echo -e "\n=== VxVM Disk Status ===" | tee -a "$LOGFILE"
vxdisk list | tee -a "$LOGFILE"

echo""
# 7. VxVM Volume Status
echo -e "\n=== VxVM Volume Status ===" | tee -a "$LOGFILE"
vxprint -ht | tee -a "$LOGFILE"

echo""
# 8. Checking for Faulty Disks
echo -e "\n=== Checking for Faulty Disks ===" | tee -a "$LOGFILE"
vxdisk list | grep -iE 'error|failed|removed|nodisk' | tee -a "$LOGFILE"

echo""
# 9. VxVM Volume/Pled/Subdisk Status
echo -e "\n=== Checking for Volume/ Plex/ Subdisk Errors ===" | tee -a "$LOGFILE"
vxprint -ht | grep -iE 'FAULT|OFFLINE|DETACHED|NODAREC' | tee -a "$LOGFILE"

echo""
# 10. Checking DMP Info
echo -e "\n=== DMP (Dynamic Multipathing) Info ===" | tee -a "$LOGFILE"
vxdmpadm getsubpaths | tee -a "$LOGFILE"

echo""
# 11. Checking DMP issues if any
echo -e "\n=== Multipath Issues (if any) ===" | tee -a "$LOGFILE"
vxdmpadm getsubpaths | grep -iE "DISABLED|FAILED|INACTIVE" | tee -a "$LOGFILE"

echo""
# 12. Check for SCSI Reservation Conflicts
echo -e "\n=== Check for SCSI Reservation Conflicts ---" | tee -a "$LOGFILE"
sg_persist --in --report-capabilities /dev/sd* 2>/dev/null | grep -i reservation | tee -a "$LOGFILE"

echo""
# 13. Checking VxVM Errors
echo -e "\n=== VxVM Errors in System Logs (Last 1 Hour) ---" | tee -a "$LOGFILE"
journalctl -S -1h | grep -Ei 'vxvm|vxdg|vxdisk|vxconfigd' | tee -a "$LOGFILE"

echo""
# 14. Checking DMPEVENT LOGS
echo -e "\n=== Check dmpevents.log if present ---" | tee -a "$LOGFILE"
if [ -f /var/adm/vx/dmpevents.log ]; then
    tail -n 15 /var/adm/vx/dmpevents.log
else
    echo "dmpevents.log not found at /var/adm/vx/"
fi | tee -a "$LOGFILE"

echo""
# 15. Check if vcs commands are available
command -v hastatus >/dev/null 2>&1 || { echo "hastatus command not found. Exiting." | tee -a "$LOGFILE"; exit 1; }

echo""
# 16. Checking VCS Cluster Status
echo -e "\n=== VCS Cluster Status ===" | tee -a "$LOGFILE"
hastatus -sum 2>/dev/null | tee -a "$LOGFILE"

echo""
# 17. Checking  Faulted Resources
echo -e "\n=== Faulted Resources (if any):" | tee -a "$LOGFILE"
hares -state | grep -i fault | tee -a "$LOGFILE"

echo ""
# 18. GAB Status
echo -e "\n=== GAB Status (gabconfig -a):" | tee -a "$LOGFILE"
gabconfig -a | tee -a "$LOGFILE"

echo ""
# 19. LLT Status
echo -e "\n=== LLT Status (lltstat -n):" | tee -a "$LOGFILE"
lltstat -n | tee -a "$LOGFILE"

echo ""
# 20. Checking for Recent VxVM/VCS Log Errors
echo -e "\n=== Checking for Recent VxVM/VCS Log Errors ==="
LOG_PATHS=("/var/VRTSvcs/log/engine_A.log" "/var/adm/messages" "/var/log/messages")
for log in "${LOG_PATHS[@]}"; do
  if [ -f "$log" ]; then
        echo -e "\n--- Checking $log ---"
        egrep -i 'vx|vxd|vcs|fail|error|panic|crash' "$log" | tail -n25
  fi
done | tee -a "$LOGFILE"
echo -e "\n=== Health Check Completed. Log saved to $LOGFILE ==="
import sys

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

start_marker = "if (magic2 == SUSFS_MAGIC && current_uid().val == 0) {"
end_marker = "#endif // #ifdef CONFIG_KSU_SUSFS"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker, start_idx)

if start_idx != -1 and end_idx != -1:
    new_block = start_marker + """
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
        if (cmd == CMD_SUSFS_ADD_SUS_PATH) {
            susfs_add_sus_path((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
        if (cmd == CMD_SUSFS_ADD_SUS_MOUNT) {
            susfs_add_sus_mount((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
        if (cmd == CMD_SUSFS_ADD_SUS_KSTAT) {
            susfs_add_sus_kstat((void __user *)*arg);
            return 0;
        }
        if (cmd == CMD_SUSFS_UPDATE_SUS_KSTAT) {
            susfs_update_sus_kstat((void __user *)*arg);
            return 0;
        }
        if (cmd == CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY) {
            susfs_add_sus_kstat((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
        if (cmd == CMD_SUSFS_ADD_TRY_UMOUNT) {
            susfs_add_try_umount((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
        if (cmd == CMD_SUSFS_SET_UNAME) {
            susfs_set_uname((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
        if (cmd == CMD_SUSFS_ENABLE_LOG) {
            susfs_set_log(1);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
        if (cmd == CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG) {
            susfs_set_cmdline_or_bootconfig((void __user *)*arg);
            return 0;
        }
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
        if (cmd == CMD_SUSFS_ADD_OPEN_REDIRECT) {
            susfs_add_open_redirect((void __user *)*arg);
            return 0;
        }
#endif
        return 0;
    }
"""
    # Replace the block
    content = content[:start_idx] + new_block + content[end_idx:]
    with open(filepath, 'w') as f:
        f.write(content)

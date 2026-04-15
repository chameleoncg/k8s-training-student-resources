#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ryan Schaaf");
MODULE_DESCRIPTION("Kernel module to demonstrate weaponizing a pod using misconfigured capabiltiies");

static int __init mod_init(void) {
  printk(KERN_INFO "[+] Module Loaded\n");
  return 0;
}

static void __exit mod_exit(void) {
  printk(KERN_INFO "[-] Module Unloaded\n");
}

module_init(mod_init);
module_exit(mod_exit);
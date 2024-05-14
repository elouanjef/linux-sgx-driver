#!/bin/bash
: '
Access to this file is granted under the SCONE COMMERCIAL LICENSE V1.0

Any use of this product using this file requires a commercial license from scontain UG, www.scontain.com.

Permission is also granted  to use the Program for a reasonably limited period of time  (but no longer than 1 month)
for the purpose of evaluating its usefulness for a particular purpose.

THERE IS NO WARRANTY FOR THIS PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING
THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU. SHOULD THE PROGRAM PROVE DEFECTIVE,
YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED ON IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY
MODIFY AND/OR REDISTRIBUTE THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE PROGRAM INCLUDING BUT NOT LIMITED TO LOSS
OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE
WITH ANY OTHER PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

Copyright (C) 2017-2021 scontain.com
'

set -e

# OOT Patches
oot_metrics_patch_content=$(cat << 'METRICS_PATCH_EOF'
From 3b47ff9dde963f0a45d577b1905f9569f686f0e7 Mon Sep 17 00:00:00 2001
From: =?UTF-8?q?F=C3=A1bio=20Silva?= <fabio@scontain.com>
Date: Wed, 2 Sep 2020 14:28:23 -0300
Subject: [PATCH] Add metrics extension

---
 sgx.h            |  2 ++
 sgx_encl.c       | 15 +++++++++++++++
 sgx_page_cache.c | 19 +++++++++++++++++++
 sgx_util.c       |  7 +++++++
 show_values.sh   | 22 ++++++++++++++++++++++
 5 files changed, 65 insertions(+)
 create mode 100755 show_values.sh

diff --git a/sgx.h b/sgx.h
index 62c19da..6a4a434 100644
--- a/sgx.h
+++ b/sgx.h
@@ -86,6 +86,8 @@
     #define MSR_IA32_SGXLEPUBKEYHASH3	0x0000008F
 #endif
 
+#define PATCH_METRICS 2
+
 struct sgx_epc_page {
 	resource_size_t	pa;
 	struct list_head list;
diff --git a/sgx_encl.c b/sgx_encl.c
index 04a1b9c..16fb79e 100644
--- a/sgx_encl.c
+++ b/sgx_encl.c
@@ -73,6 +73,14 @@
 #include <linux/slab.h>
 #include <linux/hashtable.h>
 #include <linux/shmem_fs.h>
+#include <linux/moduleparam.h>
+
+static unsigned int sgx_nr_enclaves;
+static unsigned int sgx_nr_added_pages;
+static unsigned int sgx_init_enclaves;
+module_param(sgx_init_enclaves, uint, 0440);
+module_param(sgx_nr_added_pages, uint, 0440);
+module_param(sgx_nr_enclaves, uint, 0440);
 
 struct sgx_add_page_req {
 	struct sgx_encl *encl;
@@ -221,6 +229,8 @@ static int sgx_eadd(struct sgx_epc_page *secs_page,
 	sgx_put_page((void *)(unsigned long)pginfo.secs);
 	kunmap_atomic((void *)(unsigned long)pginfo.srcpge);
 
+	sgx_nr_added_pages++;
+
 	return ret;
 }
 
@@ -678,6 +688,8 @@ int sgx_encl_create(struct sgx_secs *secs)
 	list_add_tail(&encl->encl_list, &encl->tgid_ctx->encl_list);
 	mutex_unlock(&sgx_tgid_ctx_mutex);
 
+	sgx_nr_enclaves++;
+
 	return 0;
 out_locked:
 #if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0))
@@ -970,6 +982,8 @@ int sgx_encl_init(struct sgx_encl *encl, struct sgx_sigstruct *sigstruct,
 	}
 
 	encl->flags |= SGX_ENCL_INITIALIZED;
+
+	sgx_init_enclaves++;
 	return 0;
 }
 
@@ -1021,4 +1035,5 @@ void sgx_encl_release(struct kref *ref)
 		fput(encl->pcmd);
 
 	kfree(encl);
+	sgx_nr_enclaves--;
 }
diff --git a/sgx_page_cache.c b/sgx_page_cache.c
index 77bea6e..ab79f19 100644
--- a/sgx_page_cache.c
+++ b/sgx_page_cache.c
@@ -69,6 +69,7 @@
 	#include <linux/signal.h>
 #endif
 #include <linux/slab.h>
+#include <linux/moduleparam.h>
 
 #define SGX_NR_LOW_EPC_PAGES_DEFAULT 32
 #define SGX_NR_SWAP_CLUSTER_MAX	16
@@ -81,11 +82,24 @@ DEFINE_MUTEX(sgx_tgid_ctx_mutex);
 atomic_t sgx_va_pages_cnt = ATOMIC_INIT(0);
 static unsigned int sgx_nr_total_epc_pages;
 static unsigned int sgx_nr_free_pages;
+static unsigned int sgx_nr_reclaimed;
 static unsigned int sgx_nr_low_pages = SGX_NR_LOW_EPC_PAGES_DEFAULT;
 static unsigned int sgx_nr_high_pages;
+static unsigned int sgx_nr_marked_old;
+static unsigned int sgx_nr_evicted;
+static unsigned int sgx_nr_alloc_pages;
 static struct task_struct *ksgxswapd_tsk;
 static DECLARE_WAIT_QUEUE_HEAD(ksgxswapd_waitq);
 
+module_param(sgx_nr_total_epc_pages, uint, 0440);
+module_param(sgx_nr_free_pages, uint, 0440);
+module_param(sgx_nr_low_pages, uint, 0440);
+module_param(sgx_nr_high_pages, uint, 0440);
+module_param(sgx_nr_marked_old, uint, 0440);
+module_param(sgx_nr_evicted, uint, 0440);
+module_param(sgx_nr_alloc_pages, uint, 0440);
+module_param(sgx_nr_reclaimed, uint, 0440);
+
 static int sgx_test_and_clear_young_cb(pte_t *ptep,
 #if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 3, 0))
     #if( defined(RHEL_RELEASE_VERSION) && defined(RHEL_RELEASE_CODE))
@@ -104,6 +118,7 @@ static int sgx_test_and_clear_young_cb(pte_t *ptep,
 	ret = pte_young(*ptep);
 	if (ret) {
 		pte = pte_mkold(*ptep);
+		sgx_nr_marked_old++; // only statistics counter, ok not to be completely correct...
 		set_pte_at((struct mm_struct *)data, addr, ptep, pte);
 	}
 
@@ -314,6 +329,7 @@ static bool sgx_ewb(struct sgx_encl *encl,
 static void sgx_evict_page(struct sgx_encl_page *entry,
 			   struct sgx_encl *encl)
 {
+	sgx_nr_evicted++;  // races are acceptable..
 	sgx_ewb(encl, entry);
 	sgx_free_page(entry->epc_page, encl);
 	entry->epc_page = NULL;
@@ -352,11 +368,13 @@ static void sgx_write_pages(struct sgx_encl *encl, struct list_head *src)
 		list_del(&entry->list);
 		sgx_evict_page(entry->encl_page, encl);
 		encl->secs_child_cnt--;
+		sgx_nr_reclaimed++;
 	}
 
 	if (!encl->secs_child_cnt && (encl->flags & SGX_ENCL_INITIALIZED)) {
 		sgx_evict_page(&encl->secs, encl);
 		encl->flags |= SGX_ENCL_SECS_EVICTED;
+		sgx_nr_reclaimed++;
 	}
 
 	mutex_unlock(&encl->lock);
@@ -535,6 +553,7 @@ struct sgx_epc_page *sgx_alloc_page(unsigned int flags)
 		schedule();
 	}
 
+	sgx_nr_alloc_pages++; // ignore races..
 	if (sgx_nr_free_pages < sgx_nr_low_pages)
 		wake_up(&ksgxswapd_waitq);
 
diff --git a/sgx_util.c b/sgx_util.c
index 38013e2..681ef43 100644
--- a/sgx_util.c
+++ b/sgx_util.c
@@ -66,6 +66,11 @@
 #else
 	#include <linux/mm.h>
 #endif
+#include <linux/moduleparam.h>
+
+static unsigned int sgx_loaded_back;
+module_param(sgx_loaded_back, uint, 0440);
+
 int sgx_vm_insert_pfn(struct vm_area_struct *vma, unsigned long addr, resource_size_t pa)
 {
 	int rc;
@@ -220,6 +225,8 @@ int sgx_eldu(struct sgx_encl *encl,
 		ret = -EFAULT;
 	}
 
+	sgx_loaded_back++;
+
 	kunmap_atomic((void *)(unsigned long)(pginfo.pcmd - pcmd_offset));
 	kunmap_atomic((void *)(unsigned long)pginfo.srcpge);
 	sgx_put_page(va_ptr);
diff --git a/show_values.sh b/show_values.sh
new file mode 100755
index 0000000..643f7ab
--- /dev/null
+++ b/show_values.sh
@@ -0,0 +1,22 @@
+#!/bin/bash
+#
+# (C) Christof Fetzer, 2017
+
+METRICS="sgx_nr_total_epc_pages \@!-tbs-!@
+    sgx_nr_free_pages \@!-tbs-!@
+    sgx_nr_low_pages \@!-tbs-!@
+    sgx_nr_high_pages \@!-tbs-!@
+    sgx_nr_marked_old \@!-tbs-!@
+    sgx_nr_evicted \@!-tbs-!@
+    sgx_nr_alloc_pages \@!-tbs-!@
+    sgx_nr_reclaimed \@!-tbs-!@
+    sgx_init_enclaves \@!-tbs-!@
+    sgx_nr_added_pages \@!-tbs-!@
+    sgx_nr_enclaves \@!-tbs-!@
+    sgx_loaded_back \@!-tbs-!@
+    "
+MODPATH="/sys/module/isgx/parameters/"
+
+for metric in $METRICS ; do
+    echo "$metric= `cat $MODPATH/$metric`"
+done
-- 
2.25.1
METRICS_PATCH_EOF
)
oot_metrics_patch_version=2

function remove_show_values {
	file="show_values.sh"
	if [ -f "$file" ]; then
	    rm "$file"
	    echo "$file supprimé."
	else
	    echo "$file n'existe pas."
	fi
}

function apply_oot_patches {

	remove_show_values

	echo "Applying metrics patch..."
	echo "$oot_metrics_patch_content" | sed 's/\\@!-tbs-!@$/\\/g' | patch -p1
	
}

apply_oot_patches

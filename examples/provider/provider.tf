terraform {
  required_providers {
    ytsaurus = {
      source = "registry.terraform.io/ytsaurus/ytsaurus"
    }
  }
}

# Add some size constants.
variable "MBi" {
  type    = number
  default = 1024 * 1024
}

variable "GBi" {
  type    = number
  default = 1024 * 1024 * 1024
}

# There are two options for YTsaurus provider configuration:
# cluster - YTsaurus cluster's fqdn
# token - Admin's token

# For security reasons, do not store the token option in .tf file.
# Instead, the 'token' should be stored in the $HOME/.yt/token file with the appropriate file permissions.

provider "ytsaurus" {
  cluster = "<FQDN>"
}

# Suppose we want to develop a web app for pet store management called 'Mr.Cat'.
# And our two developers, Alisa and Denis, are going to use YTsaurus for it.
# Let's create YTsaurus objects for Mr.Cat's project with Terraform.

# First, we will create a group named 'mrcat'.
resource "ytsaurus_group" "mrcat_main_group" {
  name = "mrcat"
}

# And users for Alisa and Denis.
resource "ytsaurus_user" "mrcat_alisa" {
  name = "alisa"
  member_of = [
    ytsaurus_group.mrcat_main_group.name,
  ]
}

resource "ytsaurus_user" "mrcat_denis" {
  name = "denis"
  member_of = [
    ytsaurus_group.mrcat_main_group.name,
  ]
}

# Now we can create an account with the storage resources allowed for our project and create a home directory.
# But first, we should create some ACLs.

variable "acl_mrcat_use" {
  type = list(object({
    action      = string
    subjects    = list(string)
    permissions = list(string)
  }))
  default = [
    {
      action      = "allow"
      subjects    = ["mrcat"]
      permissions = ["use"]
    },
  ]
}

variable "acl_mrcat_full_access" {
  type = list(object({
    action      = string
    subjects    = list(string)
    permissions = list(string)
  }))
  default = [
    {
      action      = "allow"
      subjects    = ["mrcat"]
      permissions = ["read", "write", "remove", "mount", "administer"]
    },
  ]
}

resource "ytsaurus_account" "mrcat_account" {
  name        = "mrcat"
  acl = var.acl_mrcat_use
  resource_limits = {
    node_count  = 1000
    chunk_count = 100000
    tablet_count = 10
    tablet_static_memory = 10 * var.GBi
    disk_space_per_medium = {
      "default" = 100 * var.GBi
      "ssd_journals" = 10 * var.GBi
    }
  }
}

# Since map_nodes store data, you can add the lifecycle/prevent_destroy terraform's option just in case.

resource "ytsaurus_map_node" "mrcat_home" {
  path        = "//home/mrdir"
  account     = ytsaurus_account.mrcat_account.name
  acl = var.acl_mrcat_full_access

  lifecycle {
    prevent_destroy = true
  }
}

# Alisa wants very fast Key-Value storage to improve the web app's user experience.
# And YTsaurus dynamic tables are suitable for this task.

# But dynamic tables won't work well on HDDs, already loaded with MapReduce batch processing tasks.
# So new media are needed. One medium for journals (WAL) and one for data.

resource "ytsaurus_medium" "ssd_journals_medium" {
  name = "ssd_journals"
  acl = var.acl_mrcat_use
}

resource "ytsaurus_medium" "ssd_data_medium" {
  name = "ssd_data"
  acl = var.acl_mrcat_use
}

# To dedicate some of the cluster's resources to a specific user, a tablet cell bundle should be created.
resource "ytsaurus_tablet_cell_bundle" "mrcat_tcb" {
  name              = "mrcat"
  tablet_cell_count = 1

  options = {
    changelog_account        = ytsaurus_account.mrcat_account.name
    changelog_primary_medium = ytsaurus_medium.ssd_journals_medium.name

    snapshot_account         = ytsaurus_account.mrcat_account.name
    snapshot_primary_medium  = "default"
  }
}

# While Alisa is working on the site and Key-Value storage, Denis wants to do analytics on user request logs.
# He wants to use a MapReduce task to process logs stored in static tables in YTsaurus storage.
# And he wants some guarantees for the running time of this task.
# To give such guarantees, we need to configure a pool for Mr.Cat's tasks with some of the cluster's CPU and memory resources.

resource "ytsaurus_scheduler_pool" "mrcat_main_pool" {
  name = "mrcat_main"
  pool_tree = "default"
  max_running_operation_count = 10
  max_operation_count = 10

  strong_guarantee_resources = {
    cpu = 10
    memory = 16 * var.GBi
  }
  resource_limits = {
    cpu = 50
    memory = 32 * var.GBi
  }
}

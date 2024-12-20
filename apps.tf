data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
}

locals {
  app_template = {
    decrypt_cert = file(var.decrypt_cert_path)
    apps_github  = var.apps_github
  }
}

# -------------------------------------------------------------------------------------
# Create VMs
# -------------------------------------------------------------------------------------

# Service account for AI VM.  Needed to reach vertex APIs.
resource "google_service_account" "ai" {
  account_id = "ai-sa-${random_string.main.result}"
  project    = local.project_id
}


# AI Application VM.
resource "google_project_iam_member" "ai" {
  project = local.project_id
  role    = "roles/owner" #"roles/aiplatform.user" #"roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.ai.email}"
}

# Create VMs with Apps

resource "google_compute_instance" "ai_vm_unprotected" {
  name         = "ai-vm-unprotected"
  machine_type = "e2-standard-4"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnetwork = module.vpc_gce.subnets_self_links[0]
    network_ip = cidrhost(local.gce_subnet_cidr, 10)
    access_config {}
  }

  service_account {
    email = google_service_account.ai.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh", local.app_template)

  // Required metadata. The values are used to authenticate to vertex APIs.
  metadata = {
    project-id  = local.project_id
    region      = local.region
  }
  tags = ["direct-internet"]
}


resource "google_compute_instance" "ai_vm_protected" {
  name         = "ai-vm-protected"
  machine_type = "e2-standard-4"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnetwork = module.vpc_gce.subnets_self_links[0]
    network_ip = cidrhost(local.gce_subnet_cidr, 11)
    access_config {}
  }

  service_account {
    email = google_service_account.ai.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh", local.app_template)

  // Required metadata. The values are used to authenticate to vertex APIs.
  metadata = {
    project-id    = local.project_id
    region        = local.region
    is-protected = "true"
  }
}

resource "google_compute_instance" "ai_vm_api" {
  name         = "ai-vm-api"
  machine_type = "e2-standard-4"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnetwork = module.vpc_gce.subnets_self_links[0]
    network_ip = cidrhost(local.gce_subnet_cidr, 12)
    access_config {}
  }

  service_account {
    email = google_service_account.ai.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata_startup_script = templatefile("${path.module}/startup-script.sh", local.app_template)

  // Required metadata. The values are used to authenticate to vertex APIs.
  metadata = {
    project-id    = local.project_id
    region        = local.region
    airs-api-key  = var.airs_api_key
    airs-profile-name = var.airs_profile_name
  }
  tags = ["direct-internet"]
}

resource "google_compute_route" "dg-default" {
  name        = "dg-dg-route"
  dest_range  = "0.0.0.0/0"
  network     = module.vpc_gce.network_id
  next_hop_gateway = "default-internet-gateway"
  priority    = 100
  tags = ["direct-internet"]
}


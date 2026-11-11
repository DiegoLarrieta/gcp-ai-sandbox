mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      email_address = "service-300000000001@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_compute_network" {
    defaults = {
      id        = "projects/reto/global/networks/vpc-hub"
      self_link = "https://www.googleapis.com/compute/v1/projects/reto/global/networks/vpc-hub"
    }
  }
  mock_resource "google_compute_ha_vpn_gateway" {
    defaults = {
      id = "projects/reto/regions/us-central1/vpnGateways/vpn"
    }
  }
  mock_resource "google_compute_router" {
    defaults = {
      id = "projects/reto/regions/us-central1/routers/cr"
    }
  }
}

mock_provider "random" {}

variables {
  project_id = "reto-terraform-abcd"
}

run "red_y_salida_controlada" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet["hub-usc1"].ip_cidr_range == "10.0.0.0/24"
    error_message = "Las subredes deben seguir docs/plan-ip.md."
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.deny_internet.priority > google_compute_network_firewall_policy_rule.allow_fqdns.priority
    error_message = "La lista de dominios debe evaluarse antes del bloqueo general."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.psc_apis.target == "all-apis"
    error_message = "Sin organización se usa el bundle all-apis."
  }
}

run "vpn_solo_cuando_se_pide" {
  command = plan

  assert {
    condition     = length(module.hybrid) == 0
    error_message = "El VPN no debe existir por defecto."
  }
}

run "vpn_con_dos_tuneles" {
  command = plan

  variables {
    enable_hybrid = true
  }

  assert {
    condition     = length(module.hybrid[0].tunnels) == 2
    error_message = "HA VPN necesita dos túneles."
  }
}

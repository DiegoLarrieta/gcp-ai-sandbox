# Pruebas de la etapa 3 con mock_provider (ADR-0005).

mock_provider "google" {
  mock_resource "google_compute_network" {
    defaults = {
      id        = "projects/acme-net-hub-abcd/global/networks/vpc-hub"
      self_link = "https://www.googleapis.com/compute/v1/projects/acme-net-hub-abcd/global/networks/vpc-hub"
    }
  }
  mock_resource "google_compute_ha_vpn_gateway" {
    defaults = {
      id = "projects/acme-net-hub-abcd/regions/us-central1/vpnGateways/vpn"
    }
  }
  mock_resource "google_compute_router" {
    defaults = {
      id = "projects/acme-net-hub-abcd/regions/us-central1/routers/cr"
    }
  }
}

mock_provider "random" {}

variables {
  tfstate_bucket = "acme-tfstate-abcd"
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      seed_project_id = "acme-seed-abcd"
    }
  }
}

override_data {
  target = data.terraform_remote_state.org
  values = {
    outputs = {
      folders = {
        root       = "folders/100000000001"
        common     = "folders/100000000002"
        ai_sandbox = "folders/100000000003"
      }
      projects = {
        net-hub     = { project_id = "acme-net-hub-abcd", number = "300000000002" }
        ai-platform = { project_id = "acme-ai-platform-abcd", number = "300000000004" }
        ai-data     = { project_id = "acme-ai-data-abcd", number = "300000000005" }
      }
    }
  }
}

run "shared_vpc_hub_and_spoke" {
  command = plan

  assert {
    condition     = google_compute_shared_vpc_host_project.hub.project == "acme-net-hub-abcd"
    error_message = "net-hub debe ser el host de la Shared VPC."
  }

  assert {
    condition     = toset([for s in google_compute_shared_vpc_service_project.spoke : s.service_project]) == toset(["acme-ai-platform-abcd", "acme-ai-data-abcd"])
    error_message = "ai-platform y ai-data deben ser spokes."
  }
}

run "subredes_segun_plan_ip" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet["hub-usc1"].ip_cidr_range == "10.0.0.0/24" && google_compute_subnetwork.subnet["ai-platform-gke"].ip_cidr_range == "10.0.16.0/20"
    error_message = "Las subredes deben seguir docs/plan-ip.md."
  }

  assert {
    condition     = alltrue([for s in google_compute_subnetwork.subnet : s.private_ip_google_access])
    error_message = "Todas las subredes deben usar Private Google Access."
  }

  assert {
    condition     = google_compute_subnetwork.subnet["hub-use4"].region == "us-east4"
    error_message = "La región alterna debe tener su subred."
  }

  assert {
    condition     = length([for r in google_compute_subnetwork.subnet["ai-platform-gke"].secondary_ip_range : r if r.ip_cidr_range == "100.64.0.0/14"]) == 1
    error_message = "GKE debe tener su rango de pods en 100.64.0.0/14."
  }
}

run "salida_solo_a_dominios_permitidos" {
  command = plan

  assert {
    condition     = contains(google_compute_network_firewall_policy_rule.allow_fqdns.match[0].dest_fqdns, "pypi.org") && contains(google_compute_network_firewall_policy_rule.allow_fqdns.match[0].dest_fqdns, "huggingface.co")
    error_message = "Deben permitirse los repositorios de paquetes y de modelos."
  }

  assert {
    condition     = google_compute_network_firewall_policy_rule.deny_internet.action == "deny" && google_compute_network_firewall_policy_rule.deny_internet.priority > google_compute_network_firewall_policy_rule.allow_fqdns.priority
    error_message = "Todo lo demás hacia Internet debe bloquearse después de la lista de dominios."
  }

  assert {
    condition     = google_compute_router_nat.nat.log_config[0].enable
    error_message = "Cloud NAT debe registrar sus conexiones."
  }
}

run "sin_rutas_a_produccion" {
  command = plan

  assert {
    condition     = google_compute_firewall_policy_association.ai_sandbox.attachment_target == "folders/100000000003"
    error_message = "El firewall jerárquico debe aplicarse a la carpeta ai-sandbox."
  }

  assert {
    condition     = google_compute_firewall_policy_rule.deny_production.action == "deny" && google_compute_firewall_policy_rule.deny_production.direction == "EGRESS"
    error_message = "Debe bloquearse la salida hacia producción."
  }
}

run "apis_por_private_service_connect" {
  command = plan

  assert {
    condition     = google_compute_global_forwarding_rule.psc_apis.target == "vpc-sc" && google_compute_global_address.psc_apis.address == "10.0.200.10"
    error_message = "Las APIs deben salir por el endpoint PSC del bundle vpc-sc."
  }

  assert {
    condition     = google_dns_record_set.psc_a["googleapis.com."].rrdatas == tolist(["10.0.200.10"])
    error_message = "restricted.googleapis.com debe resolver al endpoint PSC."
  }

  assert {
    condition     = can(regex("^[a-z][a-z0-9]{0,19}$", google_compute_global_forwarding_rule.psc_apis.name))
    error_message = "El nombre del endpoint PSC solo admite letras y números, máximo 20."
  }
}

run "sin_vpn_por_defecto" {
  command = plan

  assert {
    condition     = length(module.hybrid) == 0
    error_message = "El HA VPN solo se crea cuando se pide, para no generar costo."
  }
}

run "ha_vpn_con_bgp" {
  command = plan

  variables {
    enable_hybrid = true
  }

  assert {
    condition     = length(module.hybrid) == 1 && google_compute_subnetwork.onprem[0].ip_cidr_range == "172.16.0.0/24"
    error_message = "Con enable_hybrid se crea el on-premises simulado."
  }

  assert {
    condition     = length(module.hybrid[0].tunnels) == 2
    error_message = "HA VPN necesita dos túneles para el SLA de 99.99 %."
  }
}

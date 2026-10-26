# Valores fijos para atributos calculados que de otra forma serían cadenas
# aleatorias. Así las pruebas pueden comparar contra valores conocidos.

mock_resource "google_folder" {
  defaults = {
    name      = "folders/111111111111"
    folder_id = "111111111111"
  }
}

mock_resource "google_project" {
  defaults = {
    number = "222222222222"
  }
}

mock_resource "google_kms_crypto_key" {
  defaults = {
    id = "projects/acme-seed-abcd/locations/us-central1/keyRings/tfstate-us-central1/cryptoKeys/tfstate"
  }
}

mock_resource "google_iam_workload_identity_pool" {
  defaults = {
    name = "projects/222222222222/locations/global/workloadIdentityPools/github"
  }
}

mock_resource "google_iam_workload_identity_pool_provider" {
  defaults = {
    name = "projects/222222222222/locations/global/workloadIdentityPools/github/providers/github-actions"
  }
}

# El proveedor valida el formato de service_account_id al aplicar, así que
# la cadena aleatoria por defecto no sirve. Un mock no distingue instancias
# de un for_each: todas las cuentas reciben este mismo valor.
mock_resource "google_service_account" {
  defaults = {
    name  = "projects/acme-seed-abcd/serviceAccounts/sa-mock@acme-seed-abcd.iam.gserviceaccount.com"
    email = "sa-mock@acme-seed-abcd.iam.gserviceaccount.com"
  }
}

mock_data "google_storage_project_service_account" {
  defaults = {
    email_address = "service-222222222222@gs-project-accounts.iam.gserviceaccount.com"
  }
}

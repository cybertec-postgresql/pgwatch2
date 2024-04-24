// local requirements:
// docker
// heroku CLI
// heroku login


locals {
  heroku_region = var.heroku_private_space == null ? var.heroku_region_cr : var.heroku_region_ps
  pgw2_collector_postgres_plan = var.heroku_private_space == null ? var.pgw2_collector_postgres_plan_cr : var.pgw2_collector_postgres_plan_ps
  pgw2_monitoreddb_postgres_plan = var.heroku_private_space == null ? var.pgw2_monitoreddb_postgres_plan_cr : var.pgw2_monitoreddb_postgres_plan_ps
  pgw2_grafana_app_dynosize = var.heroku_private_space == null ? var.pgw2_grafana_app_dynosize_cr : var.pgw2_grafana_app_dynosize_ps
  pgw2_collector_app_dynosize = var.heroku_private_space == null ? var.pgw2_collector_app_dynosize_cr : var.pgw2_collector_app_dynosize_ps
  pgw2_collector_webui_app_dynosize = var.heroku_private_space == null ? var.pgw2_collector_webui_app_dynosize_cr : var.pgw2_collector_webui_app_dynosize_ps
  pgw2_monitoreddb_app_dynosize = var.heroku_private_space == null ? var.pgw2_monitoreddb_app_dynosize_cr : var.pgw2_monitoreddb_app_dynosize_ps
}

//
// pgwatch2 collector app
//
resource "heroku_app" "pgw2_collector_app" {
  name   = var.pgw2_collector_app_name
  stack   = "container"

  organization {
    name = var.heroku_team_name
  }

  region = local.heroku_region

  space = var.heroku_private_space
}

// collector logging add-on
resource "heroku_addon" "pgw2_collector_papertrail" {
  app_id = heroku_app.pgw2_collector_app.id
  plan   = "papertrail:choklad"
}

// collector Postgres add-on to store collector config/metrics and grafana config 
resource "heroku_addon" "pgw2_collector_postgres" {
  app_id = heroku_app.pgw2_collector_app.id
  plan = local.pgw2_collector_postgres_plan

  // optional - to prioritise the papertrail add-on creation as postgres takes much time 
  depends_on = [ heroku_addon.pgw2_collector_papertrail ]   
}

// collector Postgres pgwatch2 credential
resource "null_resource" "pgw2_collector_postgres_pgwatch2_credential_creation" {

  // the following provisioners are executed sequentially from the local computer

  // wait for HA when available
  provisioner "local-exec" {
    command = "WFHA_HEROKU_APP_NAME=${var.pgw2_collector_app_name} WFHA_HEROKU_PG_DB=${heroku_addon.pgw2_collector_postgres.name} ${path.module}/scripts/waitforha.sh"
  }   

  // attach the credential to the app with a terraform resource
  provisioner "local-exec" {
    command = "heroku pg:credentials:create ${heroku_addon.pgw2_collector_postgres.name} --name pgwatch2 --app ${var.pgw2_collector_app_name}"
  }

  // wait for credential provisioning as it takes time (up to 1-2 mins)
  provisioner "local-exec" {
    command = "WCP_HEROKU_APP_NAME=${var.pgw2_collector_app_name} WCP_HEROKU_PG_DB_CREDENTIAL=pgwatch2 ${path.module}/scripts/waitforcredentialprovisioning.sh"
  }  

  // to ensure provisioners are executed once the postgres addon has been created
  depends_on = [ heroku_addon.pgw2_collector_postgres ] 
}

// collector Postgres pgwatch2 credential attachment
resource "heroku_addon_attachment" "pgw2_collector_postgres_pgwatch2_credential_attachment" {
  app_id = heroku_app.pgw2_collector_app.id
  addon_id = heroku_addon.pgw2_collector_postgres.id
  name = "PGWATCH2"
  namespace = "credential:pgwatch2"

  // to ensure provisioners are executed once the postgres pgwatch2 credential has been created
  depends_on = [ null_resource.pgw2_collector_postgres_pgwatch2_credential_creation ] 
}

// build and push to heroku collector db-bootstrapper one-off dyno
resource "null_resource" "pgw2_collector_db-bootstrapper_local_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=${var.pgw2_db-bootstrapper_proc_name} HK_APP_NAME=${var.pgw2_collector_app_name} ./build-and-push-to-heroku-docker-db-bootstrapper.sh"
  }

  // to ensure provisioners are executed once the app has been created
  depends_on = [ heroku_app.pgw2_collector_app ] 
}

// run collector db-bootstrapper one-off dyno to initialize db config
resource "null_resource" "pgw2_collector_db-bootstrapper_run_config_db_init" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "heroku run db-bootstrapper -a ${var.pgw2_collector_app_name} --type=${var.pgw2_db-bootstrapper_proc_name} -e \"BOOTSTRAP_TYPE=configdb;BOOTSTRAP_ADD_TEST_MONITORING_ENTRY=false\""
  }

  // to ensure provisioners are executed once the db-bootstrapper docker image has been created and 
  // the pgwatch2_credential has been created and the logging add-on is available
  depends_on = [ null_resource.pgw2_collector_db-bootstrapper_local_docker_build_and_push,
                 heroku_addon_attachment.pgw2_collector_postgres_pgwatch2_credential_attachment,
                 heroku_addon.pgw2_collector_papertrail
  ] 
}

// run collector db-bootstrapper one-off dyno to initialize db metrics
resource "null_resource" "pgw2_collector_db-bootstrapper_run_metrics_db_init" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "heroku run db-bootstrapper -a ${var.pgw2_collector_app_name} --type=${var.pgw2_db-bootstrapper_proc_name} -e \"BOOTSTRAP_TYPE=metricsdb;BOOTSTRAP_ADD_TEST_MONITORING_ENTRY=false\""
  }

  // to ensure provisioners are executed once the db-bootstrapper docker image has been created and 
  // the pgwatch2_credential has been created and the logging add-on is available
  depends_on = [ null_resource.pgw2_collector_db-bootstrapper_local_docker_build_and_push,
                 heroku_addon_attachment.pgw2_collector_postgres_pgwatch2_credential_attachment,
                 heroku_addon.pgw2_collector_papertrail,
                 null_resource.pgw2_collector_db-bootstrapper_run_config_db_init
  ] 
}

// build and push to heroku collector daemon worker dyno
resource "null_resource" "pgw2_collector_daemon_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=${var.pgw2_collector_proc_name} HK_APP_NAME=${var.pgw2_collector_app_name} ./build-and-push-to-heroku-docker-daemon-collector.sh"
  }

  // to ensure provisioners are executed once the app has been created
  depends_on = [ heroku_app.pgw2_collector_app ] 
}

# Launch the collector worker process by scaling-up
resource "heroku_formation" "pgw2_collector_app_formation" {
  app_id     = heroku_app.pgw2_collector_app.id
  type       = var.pgw2_collector_proc_name
  quantity   = 1
  size       = local.pgw2_collector_app_dynosize
  // starting the collector only once the monitored db attachment is ready and the moniotored db init has been executed (to create a monitored db entry automatically from the collector startup script)
  depends_on = [ null_resource.pgw2_collector_db-bootstrapper_run_config_db_init, null_resource.pgw2_collector_db-bootstrapper_run_metrics_db_init, 
  heroku_addon_attachment.pgw2_collector_monitoreddb_postgres_pgwatch2_credential_attachment, null_resource.pgw2_monitored-db-bootstrapper_run_db_init ]
}



// build and push to heroku collector webui web dyno
resource "null_resource" "pgw2_collector_webui_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=web HK_APP_NAME=${var.pgw2_collector_app_name} ./build-and-push-to-heroku-docker-webui.sh"
  }

  // to ensure provisioners are executed once the app has been created and the config/metrics db has been initialized
  depends_on = [ heroku_app.pgw2_collector_app ] 
}

// config vars for webui web dyno
resource "heroku_app_config_association" "pgw2_collector_webui_app_config" {
  app_id = heroku_app.pgw2_collector_app.id

  vars = {
    PW2_WEBNOANONYMOUS = "${var.pgw2_collector_webui_webnoanonymous}"
  }

  sensitive_vars = {
    PW2_WEBPASSWORD = "${var.pgw2_collector_webui_webpassword}",
    PW2_WEBUSER = "${var.pgw2_collector_webui_webuser}",
    PW2_AES_GCM_KEYPHRASE = "${var.pgw2_collector_webui_aes_gcm_keyphrase}"  }

  depends_on = [ null_resource.pgw2_collector_db-bootstrapper_local_docker_build_and_push ] 
}

# Launch the collector web (webui) process by scaling-up
resource "heroku_formation" "pgw2_collector_webui_app_formation" {
  app_id     = heroku_app.pgw2_collector_app.id
  type       = "web"
  quantity   = 1
  size       = local.pgw2_collector_webui_app_dynosize
  depends_on = [ null_resource.pgw2_collector_webui_docker_build_and_push, null_resource.pgw2_collector_db-bootstrapper_run_config_db_init, 
  null_resource.pgw2_collector_db-bootstrapper_run_metrics_db_init, heroku_app_config_association.pgw2_collector_webui_app_config ]
}


//
// pgwatch2 monitored db app
//
resource "heroku_app" "pgw2_monitoreddb_app" {
  name   = var.pgw2_monitoreddb_app_name

  organization {
    name = var.heroku_team_name
  }

  region = local.heroku_region

  space = var.heroku_private_space
}

// monitored db logging add-on
resource "heroku_addon" "pgw2_monitoreddb_papertrail" {
  app_id = heroku_app.pgw2_monitoreddb_app.id
  plan   = "papertrail:choklad"
}

// monitored db Postgres add-on 
resource "heroku_addon" "pgw2_monitoreddb_postgres" {
  app_id = heroku_app.pgw2_monitoreddb_app.id
  plan = local.pgw2_monitoreddb_postgres_plan

  // optional - to prioritise the papertrail add-on creation as postgres takes much time 
  depends_on = [ heroku_addon.pgw2_monitoreddb_papertrail ]  
}

// monitored db Postgres pgwatch2 credential
resource "null_resource" "pgw2_monitoreddb_postgres_pgwatch2_credential_creation" {

  // the following provisioners are executed sequentially from the local computer

  // wait for HA when available
  provisioner "local-exec" {
    command = "WFHA_HEROKU_APP_NAME=${var.pgw2_monitoreddb_app_name} WFHA_HEROKU_PG_DB=${heroku_addon.pgw2_monitoreddb_postgres.name} ${path.module}/scripts/waitforha.sh"
  }  

  // attach the credential to the app with a terraform resource
  provisioner "local-exec" {
    command = "heroku pg:credentials:create ${heroku_addon.pgw2_monitoreddb_postgres.name} --name pgwatch2 --app ${var.pgw2_monitoreddb_app_name}"
  }

  // wait for credential provisioning as it takes time (up to 1-2 mins)
  provisioner "local-exec" {
    command = "WCP_HEROKU_APP_NAME=${var.pgw2_monitoreddb_app_name} WCP_HEROKU_PG_DB_CREDENTIAL=pgwatch2 ${path.module}/scripts/waitforcredentialprovisioning.sh"
  }

  // to ensure provisioners are executed once the postgres addon has been created
  depends_on = [ heroku_addon.pgw2_monitoreddb_postgres ] 
}

/* REDUNDANT NOT REQUIRED

// monitored db Postgres pgwatch2 credential attachment
resource "heroku_addon_attachment" "pgw2_monitoreddb_postgres_pgwatch2_credential_attachment" {
  app_id = heroku_app.pgw2_monitoreddb_app.id
  addon_id = heroku_addon.pgw2_monitoreddb_postgres.id
  name = "PGWATCH2"
  namespace = "credential:pgwatch2"

  // to ensure provisioners are executed once the postgres pgwatch2 credential has been created
  depends_on = [ null_resource.pgw2_monitoreddb_postgres_pgwatch2_credential_creation ] 
}

*/

// collector monitored db Postgres pgwatch2 credential attachment
resource "heroku_addon_attachment" "pgw2_collector_monitoreddb_postgres_pgwatch2_credential_attachment" {
  app_id = heroku_app.pgw2_collector_app.id
  addon_id = heroku_addon.pgw2_monitoreddb_postgres.id
  name = "PGWATCH2_MONITOREDDB_MYTARGETDB"
  namespace = "credential:pgwatch2"

  // to ensure provisioners are executed once the postgres pgwatch2 credential has been created
  depends_on = [ null_resource.pgw2_monitoreddb_postgres_pgwatch2_credential_creation ] 
}

// build and push to heroku monitored-db-bootstrapper one-off dyno
resource "null_resource" "pgw2_monitored-db-bootstrapper_local_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=${var.pgw2_monitored-db-bootstrapper_proc_name} HK_APP_NAME=${var.pgw2_monitoreddb_app_name} ./build-and-push-to-heroku-docker-monitored-db-bootstrapper.sh"
  }

  // to ensure provisioners are executed once the app has been created
  depends_on = [ heroku_app.pgw2_monitoreddb_app ] 
}

// build and push to heroku monitored db pgbench dyno
resource "null_resource" "pgw2_monitored_db_pgbench_local_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=${var.pgw2_monitored_db_pgbench_proc_name} HK_APP_NAME=${var.pgw2_monitoreddb_app_name} ./build-and-push-to-heroku-docker-pgbench.sh"
  }

  // to ensure provisioners are executed once the app has been created
  depends_on = [ heroku_app.pgw2_monitoreddb_app ] 
}

# Launch the pgbench worker process by scaling-up
resource "heroku_formation" "pgw2_monitoreddb_app_formation" {
  app_id     = heroku_app.pgw2_monitoreddb_app.id
  type       = var.pgw2_monitored_db_pgbench_proc_name
  quantity   = 1
  size       = local.pgw2_monitoreddb_app_dynosize
  depends_on = [ null_resource.pgw2_monitored_db_pgbench_local_docker_build_and_push, null_resource.pgw2_monitored-db-bootstrapper_run_db_init ]
}

// run collector monitored-db-bootstrapper one-off dyno to initialize db metrics
resource "null_resource" "pgw2_monitored-db-bootstrapper_run_db_init" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "heroku run monitored-db-bootstrapper -a ${var.pgw2_monitoreddb_app_name} --type=${var.pgw2_monitored-db-bootstrapper_proc_name}"
  }

  // to ensure provisioners are executed once the db-bootstrapper docker image has been created 
  // and pgwatch2 credential has been created on the monitored db and the logging add-on is available
  depends_on = [ null_resource.pgw2_collector_db-bootstrapper_local_docker_build_and_push,
                 null_resource.pgw2_monitoreddb_postgres_pgwatch2_credential_creation,
                 heroku_addon.pgw2_monitoreddb_papertrail
  ] 
}



//
// pgwatch2 grafana app
// 
resource "heroku_app" "pgw2_grafana_app" {
  name   = var.pgw2_grafana_app_name
  stack   = "container"

  organization {
    name = var.heroku_team_name
  }

  region = local.heroku_region

  space = var.heroku_private_space
}

// grafana logging add-on
resource "heroku_addon" "pgw2_grafana_papertrail" {
  app_id = heroku_app.pgw2_grafana_app.id
  plan   = "papertrail:choklad"
}

// collector Postgres pgwatch2_grafana credential
resource "null_resource" "pgw2_collector_postgres_pgwatch2_grafana_credential_creation" {

  // the following provisioners are executed sequentially from the local computer

  // wait for HA when available
  provisioner "local-exec" {
    command = "WFHA_HEROKU_APP_NAME=${var.pgw2_collector_app_name} WFHA_HEROKU_PG_DB=${heroku_addon.pgw2_collector_postgres.name} ${path.module}/scripts/waitforha.sh"
  }

  // attach the credential to the app with a terraform resource
  provisioner "local-exec" {
    command = "heroku pg:credentials:create ${heroku_addon.pgw2_collector_postgres.name} --name pgwatch2_grafana --app ${var.pgw2_collector_app_name}"
  }


  // wait for credential provisioning as it takes time (up to 1-2 mins)
  provisioner "local-exec" {
    command = "WCP_HEROKU_APP_NAME=${var.pgw2_collector_app_name} WCP_HEROKU_PG_DB_CREDENTIAL=pgwatch2_grafana ${path.module}/scripts/waitforcredentialprovisioning.sh"
  }

  // to ensure provisioners are executed once the postgres addon has been created
  depends_on = [ heroku_addon.pgw2_collector_postgres ] 
}

// collector Postgres pgwatch2_grafana credential attachment
resource "heroku_addon_attachment" "pgw2_collector_postgres_pgwatch2_grafana_credential_attachment" {
  app_id = heroku_app.pgw2_grafana_app.id
  addon_id = heroku_addon.pgw2_collector_postgres.id
  name = "PGWATCH2_GRAFANA"
  namespace = "credential:pgwatch2_grafana"

  // to ensure provisioners are executed once the postgres pgwatch2 credential has been created
  depends_on = [ null_resource.pgw2_collector_postgres_pgwatch2_credential_creation ] 
}

// build and push to heroku collector grafana-db-bootstrapper one-off dyno
resource "null_resource" "pgw2_grafana-db-bootstrapper_local_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=${var.pgw2_grafana-db-bootstrapper_proc_name} HK_APP_NAME=${var.pgw2_collector_app_name} ./build-and-push-to-heroku-docker-grafana-db-bootstrapper.sh"
  }

  // to ensure provisioners are executed once the app has been created
  depends_on = [ heroku_app.pgw2_grafana_app ] 
}

// run collector grafana-db-bootstrapper one-off dyno to initialize grafana db
resource "null_resource" "pgw2_grafana-db-bootstrapper_run_db_init" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "heroku run grafana-db-bootstrapper -a ${var.pgw2_collector_app_name} --type=${var.pgw2_grafana-db-bootstrapper_proc_name}"
  }

  // to ensure provisioners are executed once the grafana-db-bootstrapper docker image has been created
  // and the collector config/metrics tables have been created as Grafana dashboards uses them
  depends_on = [ null_resource.pgw2_grafana-db-bootstrapper_local_docker_build_and_push, 
  null_resource.pgw2_collector_db-bootstrapper_run_metrics_db_init, 
  null_resource.pgw2_collector_db-bootstrapper_run_config_db_init, 
  heroku_addon_attachment.pgw2_collector_postgres_pgwatch2_grafana_credential_attachment ] 
}


// build and push to heroku grafana web dyno
resource "null_resource" "pgw2_grafana_docker_build_and_push" {

  // the following provisioners are executed sequentially from the local computer
  provisioner "local-exec" {
    command = "cd ${var.pgw2_repo_local_path} && HK_PROC_TYPE=web HK_APP_NAME=${var.pgw2_grafana_app_name} ./build-and-push-to-heroku-docker-grafanaV10.sh"
  }

  // to ensure provisioners are executed once the app has been crated
  depends_on = [ heroku_app.pgw2_grafana_app ] 
}

// config vars for grafana web dyno
resource "heroku_app_config_association" "pgw2_grafana_app_config" {
  app_id = heroku_app.pgw2_grafana_app.id

  vars = {
    GF_AUTH_ANONYMOUS_ENABLED = "${var.gf_auth_anonymous_enabled}"
  }

  sensitive_vars = {
    GF_SECURITY_ADMIN_PASSWORD = "${var.gf_security_admin_password}",
    GF_SECURITY_ADMIN_USER = "${var.gf_security_admin_user}" 
  }
}

# Launch the grafana web process by scaling-up
resource "heroku_formation" "pgw2_grafana_app_formation" {
  app_id     = heroku_app.pgw2_grafana_app.id
  type       = "web"
  quantity   = 1
  size       = local.pgw2_grafana_app_dynosize
  depends_on = [ null_resource.pgw2_grafana_docker_build_and_push, null_resource.pgw2_grafana-db-bootstrapper_run_db_init ]
}


// output URLs for Grafana and WebUI
output "grafana_app_url" {
  value = heroku_app.pgw2_grafana_app.web_url
}

output "collector_webui_app_url" {
  value = heroku_app.pgw2_collector_app.web_url
}

import logging

import azure.functions as func
from azure.mgmt.resource import ResourceManagementClient
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient

def tag_compromised_vm(compute_client, network_client, group_name, location, ip, tag):
  for vm in compute_client.virtual_machines.list(group_name):
    for interface in vm.network_profile.network_interfaces:
      name = " ".join(interface.id.split('/')[-1:])
      sub = "".join(interface.id.split('/')[4])

      try:
        ip_conf = network_client.network_interfaces.get(sub, name).ip_configurations
        for x in ip_conf:
          if ip != x.private_ip_address:
            continue
          logging.info('\nTagging VM ' + vm.name)
          tags = vm.tags
          tags['status'] = tag
          async_vm_update = compute_client.virtual_machines.create_or_update(
            group_name,
            vm.name,
            {
              'location': location,
              'tags': tags
            }
          )
          async_vm_update.wait()
          return True
      except:
        raise
  return False


def main(req: func.HttpRequest) -> func.HttpResponse:
  logging.info('Python HTTP trigger function processed a request')
  tag = "quarantine"

  try:
    req_body = req.get_json()
    tenant = req_body.get('tenant')
    client_id = req_body.get('client_id')
    secret = req_body.get('secret')
    sub_id = req_body.get('subscription_id')
    ip = req_body.get('ip')
    group_name = req_body.get('group_name')
    location = req_body.get('location')
    tag = req_body.get('tag')


  except ValueError:
    logging.info(req.get_body())
    return func.HttpResponse(
      "Wrong body format. Usage:\n{\n" +
        "\ttenant: {{tenant_id}}\n" +
        "\tclient_id: {{client_id}}\n" +
        "\tsecret: {{secret}}\n" +
        "\tsub_id: {{sub_id}}\n" +
        "\tgroup_name: {{group_name}}\n" +
        "\tlocation: francecentral\n" +
        "\ttag: {{tag}}\n" +
        "\tip: 1.1.1.1\n" +
      "}",
      status_code=400
    )

  try:
    credentials = ServicePrincipalCredentials(client_id=client_id, secret=secret, tenant=tenant)

    network_client = NetworkManagementClient(credentials, sub_id)
    compute_client = ComputeManagementClient(credentials, sub_id)

    if(tag_compromised_vm(compute_client, network_client, group_name, location, ip, tag)):
      return func.HttpResponse("Tag added")

  except Exception as e:
    logging.debug(str(e))
    return func.HttpResponse(str(e), status_code=500)

  res = "IP address " + ip + " not found in " + group_name
  logging.info(res)
  return func.HttpResponse(res, status_code=409)
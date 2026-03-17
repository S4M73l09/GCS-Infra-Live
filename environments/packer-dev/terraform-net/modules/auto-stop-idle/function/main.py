import os
from googleapiclient.discovery import build

def auto_stop(event, context):
    project = os.environ["PROJECT_ID"]
    zone = os.environ["ZONE"]
    instance = os.environ["INSTANCE_NAME"]

    compute = build("compute", "v1", cache_discovery=False)
    op = compute.instances().stop(
        project=project,
        zone=zone,
        instance=instance
    ).execute()

    print(f"Deteniendo instancia {instance}. Operación: {op.get('name')}")
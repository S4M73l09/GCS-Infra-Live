from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from checkov.common.models.enums import CheckCategories, CheckResult

def includes_ssh_port(port: str) -> bool:
    if port == "22":
        return True

    if "-" not in port:
        return False

    start, end = port.split("-", 1)

    try:
        return int(start) <= 22 <= int(end)
    except ValueError:
        return False



class FirewallNoSSHOpen(BaseResourceCheck):
    def __init__(self) -> None:
        name = "Firewall must not allow SSH from 0.0.0.0/0"
        id = "CKV2_GCP_CUSTOM_3"
        supported_resources = ["google_compute_firewall"]
        categories = [CheckCategories.NETWORKING]
        super().__init__(name=name, id=id, categories=categories, supported_resources=supported_resources)

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        direction = conf.get("direction", ["INGRESS"])[0]
        if direction != "INGRESS":
            return CheckResult.PASSED

        source_ranges = conf.get("source_ranges", [])
        flat_ranges = source_ranges[0] if source_ranges and isinstance(source_ranges[0], list) else source_ranges
        if "0.0.0.0/0" not in flat_ranges:
            return CheckResult.PASSED

        allow_blocks = conf.get("allow", [])
        if allow_blocks and isinstance(allow_blocks[0], list):
            allow_blocks = allow_blocks[0]

        for allow in allow_blocks:
            protocol = allow.get("protocol", [""])[0]
            ports    = allow.get("ports", [])
            flat_ports = ports[0] if ports and isinstance(ports[0], list) else ports

            if protocol == "all":
                return CheckResult.FAILED

            if protocol == "tcp" and not flat_ports:
                return CheckResult.FAILED

            if protocol == "tcp" and any(includes_ssh_port(str(port)) for port in flat_ports):
                return CheckResult.FAILED


        return CheckResult.PASSED

check = FirewallNoSSHOpen()
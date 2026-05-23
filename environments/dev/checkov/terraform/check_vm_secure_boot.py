from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from checkov.common.models.enums import CheckCategories, CheckResult

class VMSecureBoot(BaseResourceCheck):
    def __init__(self) -> None:
        name = "VM must enable secure boot"
        id = "CKV2_GCP_CUSTOM_2"
        supported_resources = ["google_compute_instance"]
        categories = [CheckCategories.GENERAL_SECURITY]
        super().__init__(name=name, id=id, categories=categories, supported_resources=supported_resources)

    def scan_resource_conf(self, conf: dict) -> CheckResult:
        shielded = conf.get("shielded_instance_config", [])
        if not shielded:
            return CheckResult.FAILED

        secure_boot = shielded[0].get("enable_secure_boot", [False])[0]
        return CheckResult.PASSED if secure_boot is True else CheckResult.FAILED


check = VMSecureBoot()
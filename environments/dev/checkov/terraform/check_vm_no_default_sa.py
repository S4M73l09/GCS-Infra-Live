from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from checkov.common.models.enums import CheckCategories, CheckResult

class VMNoDefaultSA(BaseResourceCheck):
    def __init__(self) -> None:
        name = "VM must not use default service account"
        id = "CKV2_GCP_CUSTOM_1"
        supported_resources = ["google_compute_instance"]
        categories = [CheckCategories.IAM]
        super().__init__(name=name, id=id, categories=categories, supported_resources=supported_resources)
    
    def scan_resource_conf(self, conf: dict) -> CheckResult:
        sa_blocks = conf.get("service_account", [])
        if not sa_blocks:
            return CheckResult.FAILED

        email = sa_blocks[0].get("email", [""])[0]
        if email == "default":
            return CheckResult.FAILED
        return CheckResult.PASSED


check = VMNoDefaultSA()
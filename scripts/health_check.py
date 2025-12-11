#!/usr/bin/env python3
import os
import requests
from datetime import datetime

# URL de tu Prometheus (ajusta IP/DNS y puerto)
PROM_URL = os.getenv("PROM_URL", "http://TU_IP_O_DNS_PROMETHEUS:9090")

# Umbrales
CPU_WARN = 70
CPU_CRIT = 90
RAM_WARN = 80
RAM_CRIT = 90


def prom_query(query):
    """Lanza una query a Prometheus y devuelve un float o None si no hay datos."""
    try:
        r = requests.get(
            f"{PROM_URL}/api/v1/query",
            params={"query": query},
            timeout=10,
        )
        r.raise_for_status()
    except requests.exceptions.RequestException:
        return None

    data = r.json().get("data", {}).get("result", [])
    if not data:
        return None
    return float(data[0]["value"][1])


def get_cpu_usage():
    # Ajusta esta query según tu node_exporter
    q = 'avg(rate(node_cpu_seconds_total{mode!="idle"}[5m])) * 100'
    return prom_query(q)


def get_ram_usage():
    # RAM usada (%) = 100 - (MemAvailable / MemTotal * 100)
    total = prom_query("node_memory_MemTotal_bytes")
    avail = prom_query("node_memory_MemAvailable_bytes")
    if total is None or avail is None:
        return None
    used_pct = 100 - (avail / total * 100)
    return used_pct


def get_http_5xx():
    # Ajusta el nombre de la métrica a tu exporter (nginx, traefik, etc.)
    # Ejemplo genérico:
    q = 'sum(increase(http_requests_total{status=~"5.."}[5m]))'
    val = prom_query(q)
    if val is None:
        return None
    return val


def decide_status(cpu, ram, http_5xx):
    severity = "OK"
    reasons = []

    if cpu is not None:
        if cpu >= CPU_CRIT:
            severity = "CRIT"
            reasons.append(f"CPU muy alta ({cpu:.1f}%).")
        elif cpu >= CPU_WARN and severity != "CRIT":
            severity = "WARN"
            reasons.append(f"CPU elevada ({cpu:.1f}%).")

    if ram is not None:
        if ram >= RAM_CRIT:
            severity = "CRIT"
            reasons.append(f"Uso de RAM muy alto ({ram:.1f}%).")
        elif ram >= RAM_WARN and severity != "CRIT":
            severity = "WARN"
            reasons.append(f"Uso de RAM elevado ({ram:.1f}%).")

    if http_5xx is not None and http_5xx > 0:
        if severity == "OK":
            severity = "WARN"
        reasons.append(
            f"Se han detectado {http_5xx:.0f} errores HTTP 5xx en los últimos 5 minutos."
        )

    return severity, reasons


def estado_from_value(val, warn, crit):
    if val is None:
        return "❓ N/D"
    if val >= crit:
        return "🛑 CRIT"
    if val >= warn:
        return "⚠ WARN"
    return "✅ OK"


def make_dashboard_md(now, severity, cpu, ram, http_5xx, reasons):
    # Cabecera de estado
    if severity == "OK":
        estado_icon = "🟢"
        estado_texto = (
            "Todo ha sido analizado y todo se encuentra dentro de los parámetros esperados.\n"
            "No se han detectado fallos críticos conocidos en este intervalo."
        )
    elif severity == "WARN":
        estado_icon = "🟠"
        estado_texto = (
            "Se han detectado condiciones que podrían requerir atención preventiva.\n"
            "No es urgente, pero merece la pena echar un vistazo."
        )
    else:
        estado_icon = "🔴"
        estado_texto = (
            "Se han detectado problemas críticos que requieren intervención lo antes posible.\n"
            "Revisar métricas y servicios afectados cuanto antes."
        )

    # Resumen rápido
    resumen_lines = []

    # CPU
    if cpu is not None:
        if cpu >= CPU_WARN:
            resumen_lines.append(
                f"- **CPU:** {cpu:.1f}% → Procesador por encima del {CPU_WARN}%. "
                "Se recomiendan medidas preventivas si esta situación se mantiene en el tiempo."
            )
        else:
            resumen_lines.append(
                f"- **CPU:** {cpu:.1f}% → Carga baja o moderada, sin signos de estrés significativo."
            )
    else:
        resumen_lines.append("- **CPU:** No se ha podido obtener el uso de CPU.")

    # RAM
    if ram is not None:
        if ram >= RAM_WARN:
            resumen_lines.append(
                f"- **RAM:** {ram:.1f}% → Consumo de memoria elevado. "
                "Puede ser buen momento para revisar procesos o considerar optimizaciones."
            )
        else:
            resumen_lines.append(
                f"- **RAM:** {ram:.1f}% → Uso de memoria dentro de un rango cómodo, sin comportamientos anómalos visibles."
            )
    else:
        resumen_lines.append("- **RAM:** No se ha podido obtener el uso de RAM.")

    # Errores 5xx
    if http_5xx is not None:
        if http_5xx > 0:
            resumen_lines.append(
                f"- **Errores 5xx (últimos 5 min):** {http_5xx:.0f} → "
                "Se han registrado errores en el plano HTTP. Conviene revisar logs de aplicación / proxy."
            )
        else:
            resumen_lines.append(
                "- **Errores 5xx (últimos 5 min):** 0 → Nada de fallos críticos conocidos en el plano HTTP."
            )
    else:
        resumen_lines.append("- **Errores 5xx:** No se ha podido obtener información.")

    resumen_md = "\n".join(resumen_lines)

    cpu_estado = estado_from_value(cpu, CPU_WARN, CPU_CRIT)
    ram_estado = estado_from_value(ram, RAM_WARN, RAM_CRIT)
    if http_5xx is None:
        err_estado = "❓ N/D"
    elif http_5xx == 0:
        err_estado = "✅ OK"
    else:
        err_estado = "⚠ WARN"

    md = []
    md.append(f"# 🩺 Health report – {now} UTC\n")
    md.append(f"## {estado_icon} Estado general\n")
    md.append(estado_texto + "\n")
    md.append("---\n")
    md.append("## 📊 Resumen rápido\n")
    md.append(resumen_md + "\n")
    md.append("---\n")
    md.append("## 📌 Detalle de métricas\n")
    md.append("| Métrica                     | Valor        | Umbral WARN | Umbral CRIT | Estado   |")
    md.append("|----------------------------|--------------|-------------|-------------|----------|")

    if cpu is not None:
        md.append(
            f"| CPU media últimos 5 min    | {cpu:.1f} %     | {CPU_WARN} %        | {CPU_CRIT} %        | {cpu_estado} |"
        )
    else:
        md.append(
            "| CPU media últimos 5 min    | N/D          | N/D         | N/D         | ❓ N/D   |"
        )

    if ram is not None:
        md.append(
            f"| RAM usada                  | {ram:.1f} %     | {RAM_WARN} %        | {RAM_CRIT} %        | {ram_estado} |"
        )
    else:
        md.append(
            "| RAM usada                  | N/D          | N/D         | N/D         | ❓ N/D   |"
        )

    if http_5xx is not None:
        md.append(
            f"| Errores HTTP 5xx (5 min)   | {http_5xx:.0f}          | > 0         | > 10        | {err_estado} |"
        )
    else:
        md.append(
            "| Errores HTTP 5xx (5 min)   | N/D          | N/D         | N/D         | ❓ N/D   |"
        )

    md.append("\n---\n")
    md.append("## 🧠 Comentario del sistema\n")

    if severity == "OK":
        md.append(
            "El sistema se encuentra en un estado saludable. No se observan patrones de carga ni errores "
            "que indiquen problemas inminentes.\n"
            "Puedes seguir trabajando con normalidad.\n"
        )
    elif severity == "WARN":
        md.append(
            "Aunque el sistema sigue operativo, hay indicadores que merece la pena vigilar.\n"
            "Si estas condiciones se mantienen o empeoran, podría ser recomendable ajustar recursos "
            "o revisar servicios concretos.\n"
        )
    else:
        md.append(
            "Se recomienda revisar cuanto antes los servicios afectados, métricas históricas y logs de aplicación.\n"
            "Este estado indica riesgo real de impacto en disponibilidad o rendimiento.\n"
        )

    if reasons:
        md.append("\n### Detalles detectados\n")
        for r in reasons:
            md.append(f"- {r}")
        md.append("")

    return "\n".join(md)


def make_offline_dashboard_md(now, reasons):
    md = []
    md.append(f"# 🩺 Health report – {now} UTC\n")
    md.append("## ⚪ Estado general: VM apagada o inaccesible\n")
    md.append(
        "No se han podido recoger métricas desde Prometheus. Esto suele indicar que la VM está apagada, "
        "suspendida o que no es accesible desde el runner de GitHub Actions.\n"
    )
    md.append("---\n")
    md.append("## 📊 Resumen rápido\n")
    md.append("- **CPU:** N/D (VM no accesible)\n")
    md.append("- **RAM:** N/D (VM no accesible)\n")
    md.append("- **Errores 5xx:** N/D (VM no accesible)\n")
    md.append("---\n")
    md.append("## 🧠 Comentario del sistema\n")
    md.append(
        "Si has apagado o suspendido la VM de forma intencionada para ahorrar costes, "
        "puedes ignorar este informe.\n"
        "Si no esperabas que la VM estuviera apagada, revisa el estado de la instancia en GCP.\n"
    )

    if reasons:
        md.append("\n### Detalles\n")
        for r in reasons:
            md.append(f"- {r}")
        md.append("")

    return "\n".join(md)


def main():
    now_dt = datetime.utcnow()
    now = now_dt.strftime("%Y-%m-%d %H:%M:%S")

    cpu = get_cpu_usage()
    ram = get_ram_usage()
    http_5xx = get_http_5xx()

    # Si no hay métricas, tratamos como OFFLINE
    if cpu is None and ram is None and http_5xx is None:
        severity = "OFFLINE"
        reasons = [
            "No se han podido obtener métricas de Prometheus. La VM puede estar apagada o inaccesible."
        ]
        body = make_offline_dashboard_md(now, reasons)
    else:
        severity, reasons = decide_status(cpu, ram, http_5xx)
        body = make_dashboard_md(now, severity, cpu, ram, http_5xx, reasons)

    os.makedirs("reports", exist_ok=True)
    now_safe = now_dt.strftime("%Y-%m-%d_%H-%M-%S")
    report_file = f"reports/health_{now_safe}.md"

    with open(report_file, "w", encoding="utf-8") as f:
        f.write(body)

    # Esto lo lee el workflow
    print(f"REPORT_FILE={report_file}")
    print(f"SEVERITY={severity}")


if __name__ == "__main__":
    main()

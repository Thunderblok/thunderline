# SBOM & Vulnerability Scan Commands

- Generate SBOM (Syft): syft packages dir:. -o json > ops/reports/sbom/syft.json
- Scan vulnerabilities (Grype): grype sbom:ops/reports/sbom/syft.json -o json > ops/reports/sbom/grype.json
- Docker image SBOM: syft <image:tag> -o spdx-json > ops/reports/sbom/image.spdx.json

Optional CycloneDX:

- cyclonedx-gomod or cyclonedx-npm for language-specific SBOMs.

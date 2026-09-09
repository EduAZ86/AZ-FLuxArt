# AZ-FLuxArt

**Editor de imágenes nativo para macOS** escrito en Swift, con edición asistida por IA que corre **100 % en local**.

La característica distintiva del proyecto es el uso de un modelo de generación de imágenes ejecutado **en tu propia Mac**: **FLUX.2 Klein 4B (8-bit "S")**, corriendo sobre **MLX** y **Metal** para aprovechar al máximo el rendimiento de los chips de Apple.

## Características

- **Edición completa por capas**: texto, stickers, dibujo, borrador y transformaciones (voltear, rotar, duplicar).
- **Ajustes fotográficos**: brillo, contraste, saturación, exposición y temperatura.
- **Efectos y recorte** con ratios predefinidos (1:1, 16:9, 4:5, etc.).
- **IA local con FLUX.2 Klein 4B**: la edición inteligente (mejora, quitar fondo, expandir, reemplazar) se ejecuta sobre el modelo descargado mediante MLX/Metal, sin depender de la nube ni enviar tus imágenes a servidores externos.
- **Privacidad por diseño**: todo el procesamiento ocurre en el dispositivo.

## Requisitos

- macOS 14.0 o posterior (SDK `MACOSX_DEPLOYMENT_TARGET = 14.0`).
- Xcode para compilar el proyecto.
- Apple Silicon (chip M-series) para sacar el máximo partido a la aceleración de Metal y MLX.

## Construcción

```bash
xcodebuild build \
  -project AZ-FLuxArt.xcodeproj \
  -scheme AZ-FLuxArt \
  -destination 'platform=macOS'
```

O abrí `AZ-FLuxArt.xcodeproj` en Xcode y pulsá *Run*.

## Estado del proyecto

En desarrollo activo (v0.1.0). La interfaz de edición clásica está operativa y se está integrando la pila de IA local: la UI de la herramienta IA (descarga del modelo) ya está en marcha, conectada al flujo de instalación de FLUX.2 Klein 4B 8-bit a través de MLX/Metal.

## Stack

| Componente | Tecnología |
|---|---|
| Lenguaje / UI | Swift / SwiftUI |
| Aceleración de IA | MLX (Swift) sobre Metal |
| Modelo de imágenes | FLUX.2 Klein 4B — 8-bit "S" |
| Plataforma | macOS |

## Licencia

Sin definir aún.

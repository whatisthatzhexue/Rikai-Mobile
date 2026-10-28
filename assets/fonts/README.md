# Fonts

Rikai-Mobile uses **HarmonyOS Sans SC Regular** as its UI font. The font file is
**not distributed in this repository** (and is excluded by `.gitignore`); each
developer or user must download it themselves before building the app.

## Required file

```text
assets/fonts/HarmonyOS_Sans_SC_Regular.ttf
```

Size: approximately 7.9 MB. The file must be a valid TrueType font; renaming a
different font to this path is not supported.

## Download

Download "HarmonyOS Sans" from Huawei's official HarmonyOS design resources:

- <https://developer.huawei.com/consumer/cn/design/resource/>

Extract the Simplified Chinese (SC) Regular face and place it at the path above.
The font is free to use under the **HarmonyOS Sans Fonts License Agreement**
(including commercial use); see Huawei's download page for the authoritative
license text.

## Build behavior

`pubspec.yaml` declares the font family. Flutter fails to build if the file is
missing, with an "unable to find asset" error. Download the font before running
`flutter pub get`/`flutter build`.

The font is not part of the OCR/UniDic/MDict data and is not downloaded at
runtime by the app.

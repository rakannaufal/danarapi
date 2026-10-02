from pathlib import Path
import colorsys

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "danarapi_assets"
WEB = ROOT / "apps/web/public/brand/danarapi"
NATIVE = ROOT / "apps/ios/DanarapiApp/Assets.xcassets"
PALETTES = {
    "light": {"primary": "#09746C", "mint": "#BAF4DE", "peach": "#FDCEB2", "canvas": "#FBFCFB", "ink": "#18343B"},
    "dark": {"primary": "#7BDDC2", "mint": "#9DE4C0", "peach": "#FDCBAC", "canvas": "#0A1624", "ink": "#FBFCFB"},
}


def rgb(value):
    return tuple(bytes.fromhex(value.removeprefix("#")))


def trimmed(image, square=False):
    bounds = image.getchannel("A").getbbox()
    cropped = image.crop(bounds) if bounds else image
    padding = round(max(cropped.size) * 0.035)
    cropped = ImageOps.expand(cropped, border=padding, fill=(0, 0, 0, 0))
    if not square:
        return cropped
    result = Image.new("RGBA", (512, 512))
    scale = min(480 / cropped.width, 480 / cropped.height)
    cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)), Image.Resampling.LANCZOS)
    result.alpha_composite(cropped, ((512 - cropped.width) // 2, (512 - cropped.height) // 2))
    return result


def recolored(image, theme, wordmark=False, illustration=False):
    palette = {key: rgb(value) for key, value in PALETTES[theme].items()}
    result = image.copy()
    pixels = []
    for red, green, blue, alpha in image.get_flattened_data():
        if not alpha:
            pixels.append((red, green, blue, alpha))
            continue
        hue, saturation, brightness = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if wordmark:
            kind = "primary" if green > red + 25 and green > blue else "ink"
        elif illustration and brightness < 0.14:
            kind = "canvas" if theme == "dark" else "ink"
        elif illustration and saturation < 0.10:
            kind = "ink" if theme == "dark" else "canvas"
        elif hue < 0.17 and red > blue:
            kind = "peach"
        elif min(red, green, blue) > 105:
            kind = "mint"
        else:
            kind = "primary"
        pixels.append((*palette[kind], alpha))
    result.putdata(pixels)
    return result


def background(image, theme):
    palette = {key: rgb(value) for key, value in PALETTES[theme].items()}
    result = image.convert("RGB")
    pixels = []
    for red, green, blue in result.get_flattened_data():
        mint_weight = min(max((green - red) / 55, 0), 1) * (0.55 if theme == "light" else 0.24)
        peach_weight = min(max((red - blue) / 70, 0), 1) * (0.65 if theme == "light" else 0.20)
        base_weight = 1 - mint_weight - peach_weight
        pixels.append(tuple(round(palette["canvas"][channel] * base_weight + palette["mint"][channel] * mint_weight + palette["peach"][channel] * peach_weight) for channel in range(3)))
    result.putdata(pixels)
    return result


def save_asset(name, catalog, images):
    directory = NATIVE / f"{catalog}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
    for theme, image in images.items():
        image.save(directory / f"{name}-{theme}.png", optimize=True)
        image.save(WEB / f"{name}-{theme}.webp", lossless=name != "background", quality=88, method=6)


def main():
    WEB.mkdir(parents=True, exist_ok=True)
    logo = trimmed(Image.open(SOURCE / "logo.png").convert("RGBA"), square=True)
    logos = {theme: recolored(logo, theme) for theme in PALETTES}
    save_asset("logo", "AppLogo", logos)
    wordmark = trimmed(Image.open(SOURCE / "danarapi_text.png").convert("RGBA"))
    save_asset("danarapi_text", "danarapi_text", {theme: recolored(wordmark, theme, wordmark=True) for theme in PALETTES})
    wallpaper = Image.open(SOURCE / "background.png")
    save_asset("background", "background", {theme: background(wallpaper, theme) for theme in PALETTES})
    for identifier in range(1, 4):
        name = f"onboarding_{identifier}"
        image = trimmed(Image.open(SOURCE / f"{name}.png").convert("RGBA"), square=True)
        save_asset(name, name, {"light": image, "dark": recolored(image, "dark", illustration=True)})
    icon = Image.new("RGB", (1024, 1024), PALETTES["light"]["canvas"])
    icon_logo = logos["light"].resize((860, 860), Image.Resampling.LANCZOS)
    icon.paste(icon_logo, (82, 82), icon_logo)
    icon.save(NATIVE / "AppIcon.appiconset/AppIcon.png", optimize=True)
    for theme, image in logos.items():
        image.resize((64, 64), Image.Resampling.LANCZOS).save(WEB / f"favicon-{theme}.png", optimize=True)


if __name__ == "__main__":
    main()

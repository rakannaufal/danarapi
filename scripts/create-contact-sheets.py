from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'apps/web/artifacts/visual'
screens = ['beranda', 'input', 'split-bill', 'perlu-ditinjau', 'laporan']
for browser in ['chromium', 'webkit']:
    directory = root if browser == 'chromium' else root / browser
    for size in ['390', '1440', '375-text200']:
        for theme in ['light', 'dark']:
            images = []
            for screen in screens:
                image = Image.open(directory / f'{screen}-{size}-{theme}.png').convert('RGB')
                image.thumbnail((300, 1500))
                images.append((screen, image))
            height = max(image.height for _, image in images) + 40
            sheet = Image.new('RGB', (len(images) * 320, height), '#d8dde5')
            draw = ImageDraw.Draw(sheet)
            for index, (screen, image) in enumerate(images):
                draw.text((index * 320 + 10, 12), f'{browser} {screen} {size} {theme}', fill='#17303a')
                sheet.paste(image, (index * 320 + 10, 35))
            sheet.save(directory / f'contact-{size}-{theme}.jpg', quality=88)

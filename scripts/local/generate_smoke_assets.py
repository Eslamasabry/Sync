from __future__ import annotations

import argparse
import wave
import zipfile
from pathlib import Path


def build_epub(epub_path: Path, *, title: str, text: str) -> None:
    with zipfile.ZipFile(epub_path, "w") as archive:
        archive.writestr(
            "mimetype",
            "application/epub+zip",
            compress_type=zipfile.ZIP_STORED,
        )
        archive.writestr(
            "META-INF/container.xml",
            """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>""",
        )
        archive.writestr(
            "OEBPS/content.opf",
            f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="BookId">sample-book</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chap1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap1"/>
  </spine>
</package>""",
        )
        archive.writestr(
            "OEBPS/nav.xhtml",
            """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops">
      <ol><li><a href="chapter1.xhtml">Chapter 1</a></li></ol>
    </nav>
  </body>
</html>""",
        )
        archive.writestr(
            "OEBPS/chapter1.xhtml",
            f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body>
    <section id="chapter-1">
      <h1>Chapter 1</h1>
      <p>{text}</p>
    </section>
  </body>
</html>""",
        )


def build_wav(wav_path: Path, *, duration_seconds: int) -> None:
    sample_rate = 16_000
    frame_count = sample_rate * duration_seconds
    with wave.open(str(wav_path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(b"\x00\x00" * frame_count)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate smoke-test EPUB and WAV assets.")
    parser.add_argument(
        "--output-dir",
        default="tmp/smoke",
        help="Directory where the sample EPUB and WAV should be written.",
    )
    parser.add_argument(
        "--title",
        default="Local Demo",
        help="EPUB title to embed in the generated sample file.",
    )
    parser.add_argument(
        "--text",
        default="Call me Ishmael.",
        help="Paragraph text to place in the generated EPUB.",
    )
    parser.add_argument(
        "--duration-seconds",
        type=int,
        default=2,
        help="Length of the generated silent WAV file.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    epub_path = output_dir / "sample.epub"
    wav_path = output_dir / "sample.wav"

    build_epub(epub_path, title=args.title, text=args.text)
    build_wav(wav_path, duration_seconds=args.duration_seconds)

    print(epub_path.resolve())
    print(wav_path.resolve())


if __name__ == "__main__":
    main()

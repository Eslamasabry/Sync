# Product Requirements Document

## 1. Summary

This project is an open-source system that syncs an EPUB book with a matching audiobook and highlights each word as the audio plays. The product removes the need for pre-made sync files, manual chapter mapping, or chapter-based audio splitting by generating word-level timing automatically.

The system will use a Python backend to parse books, transcribe audio, match speech to text, and generate sync data. A Flutter client will use that sync data to show live highlighting, smooth playback, and offline reading.

## 2. Contacts

| Name | Role | Comment |
| --- | --- | --- |
| TBD | Product owner | Owns scope, roadmap, and release decisions |
| TBD | Backend lead | Owns alignment pipeline, APIs, queue, and storage |
| TBD | Flutter lead | Owns reader UX, playback, highlighting, and offline mode |
| TBD | ML / speech lead | Owns transcription quality, forced alignment, and evaluation |
| TBD | Open-source maintainer | Owns contribution flow, docs, and community support |

## 3. Background

### Context

Many users already own both an ebook and its audiobook, but most reading tools cannot sync them automatically. Existing tools often depend on publisher-authored sync metadata, chapter-level references, or manual setup. That makes them weak for open libraries, public-domain books, indie content, and personal collections.

### Why now

Automatic sync is more practical now because open speech models, forced alignment tools, and mobile playback frameworks are mature enough to support a first usable version. Open-source readers and language-learning tools also have growing demand for better audio-text sync.

### Opportunity

If this works well, the project becomes useful in three ways:

1. A direct tool for readers who want immersive reading.
2. A base platform for accessibility and language-learning apps.
3. An open-source engine other developers can extend for EPUB, PDF, subtitles, or other media sync problems.

## 4. Objective

### Objective

Build an open-source system that can take an EPUB and a matching MP3 audiobook, generate word-level alignment automatically, and play the book with live word highlighting in a Flutter reader.

### Why it matters

For users, this makes reading with audio far easier and more engaging. For developers, it provides a reusable sync pipeline that does not depend on closed formats or manual labeling.

### Strategic fit

This project fits an open, extensible product strategy:

- Open-source first
- Works with common input formats
- Avoids locked vendor sync formats
- Supports future reuse for accessibility, education, and reading apps

### Key Results

| ID | Key Result | Target |
| --- | --- | --- |
| KR1 | Word alignment accuracy on matched book/audio pairs | 90%+ |
| KR2 | End-to-end sync generation speed | Less than 10x real-time audio length |
| KR3 | Supported audiobook length in one project | Up to 20 hours |
| KR4 | Reader highlight latency during playback | Under 50 ms |
| KR5 | Successful completion rate for clean matched inputs | 80%+ in MVP test corpus |
| KR6 | Offline playback with downloaded sync data | 100% for completed jobs |

### Non-goals for MVP

- Speech synthesis
- Audiobook production tooling
- DRM-protected ebook support
- Multi-speaker diarization
- Human correction or authoring tools
- Cloud account sync

## 5. Market Segment(s)

### Primary segments

1. Readers who want immersive read-and-listen playback.
2. Language learners who benefit from hearing and seeing each word together.
3. Accessibility users who need stronger text-following support.
4. Ebook and audiobook collectors with personal libraries.
5. Developers building reading or education apps on top of an open sync engine.

### Jobs to be done

- "When I listen to a book, I want the text to follow the narration so I do not lose my place."
- "When I study a language, I want to hear and see the exact word at the same time so I can improve listening and reading together."
- "When I build a reading app, I want a reusable alignment pipeline so I do not need to create sync files by hand."

### Constraints

- Audio and text may not match perfectly.
- Books may have front matter, footnotes, copyright pages, or formatting noise.
- Audiobooks may be split into many files or delivered as one long file.
- Some users will need offline use after sync is generated.
- The system must remain open-source friendly and not depend on private licensed metadata.

## 6. Value Proposition(s)

### Core value

The product gives users automatic word-level sync between an EPUB and audiobook without requiring pre-authored sync data, chapter mapping, or manual markup.

### Customer gains

- Easier focus during long listening sessions
- Better comprehension for language learning
- Better accessibility for users who need text-following support
- Use of personal book and audio files instead of closed ecosystems

### Pains removed

- No manual chapter matching
- No need to cut audio by chapter
- No need to author sync markup
- Fewer dead ends when sync metadata does not exist

### Differentiation

Compared with standard ebook readers and audiobook apps, this product aims to be:

- Automatic instead of hand-authored
- Word-level instead of chapter-level
- Open-source instead of locked to one store or platform
- Developer-friendly instead of consumer-only

## 7. Solution

### 7.1 UX and User Flow

#### Main flow

1. User imports an EPUB file.
2. User imports one MP3 or a set of MP3 files.
3. Backend creates a book project and starts an alignment job.
4. User sees job status: queued, processing, complete, or failed.
5. When complete, the Flutter reader opens the book with synced playback.
6. As audio plays, the current word is highlighted and the text view scrolls smoothly.
7. User can tap words or text to seek playback.

#### Reader layout

```text
-------------------------
| Text Reader           |
| highlighted word      |
|                       |
-------------------------
| progress bar          |
| play pause speed      |
-------------------------
```

#### Core UX requirements

- Smooth scrolling during playback
- Stable highlight updates with no visible flicker
- Fast tap-to-seek from text to audio
- Clear job states and useful failure messages
- Offline playback once sync data is downloaded

### 7.2 Key Features

#### Feature 1: Import Book and Audio

Inputs:

- EPUB file
- Single MP3 or multiple MP3 files

System behavior:

- Extract book text and metadata
- Store source assets
- Create a project and alignment job

Output model:

```text
Book Project
 ├ EPUB text
 ├ audio
 └ alignment job
```

#### Feature 2: EPUB Processing

The system parses the EPUB and extracts:

- paragraphs
- sentences
- words

The system normalizes:

- punctuation
- quotes
- numbers
- whitespace
- repeated separators
- front matter noise where possible

Output:

- ordered token list
- token index
- EPUB location map such as CFI or equivalent position marker

#### Feature 3: Audio Transcription

The system runs speech-to-text on the audiobook and stores:

- transcript words
- timestamps
- confidence scores

This step must support long-form audio and segmented processing to avoid failure on long books.

#### Feature 4: Text Matching

The system maps transcript tokens to book tokens using:

- fuzzy matching
- dynamic programming
- sliding window search

Goal:

- transcript words -> EPUB words

This step must tolerate:

- small wording differences
- skipped phrases
- short insertions
- punctuation mismatch

#### Feature 5: Forced Alignment

The system refines rough transcript timing into precise word timing for matched sections.

Output:

- word start timestamp
- word end timestamp
- confidence or match quality score

#### Feature 6: Sync File Generation

The system generates a portable JSON sync file.

Example:

```json
{
  "book_id": "123",
  "tokens": [
    {
      "word": "Hello",
      "start": 1200,
      "end": 1400,
      "cfi": "/6/2/4"
    }
  ]
}
```

The file should also support future extension for:

- sentence groups
- confidence values
- skipped ranges
- audio file references for multipart books

#### Feature 7: Word-by-Word Reader

The Flutter app displays:

- EPUB text
- current playback position
- current highlighted word
- audio controls

Core behavior:

- audio time drives active word highlight
- viewport follows playback
- user taps on a word or text span to seek

#### Feature 8: Playback Controls

Required controls:

- play and pause
- playback speed
- rewind 15 seconds
- seek via progress bar
- tap word to jump audio
- tap text to jump playback

#### Feature 9: Offline Mode

After alignment is complete, the app can download:

- book metadata
- sync file
- needed audio references

Once downloaded, highlighting and playback must work without internet access.

### 7.3 Technology

#### Backend

- Python
- FastAPI for API layer
- Celery and Redis for job queue
- WhisperX for transcription
- Montreal Forced Aligner or Aeneas for forced alignment
- ebooklib for EPUB parsing
- Postgres for metadata
- Object storage for source files and outputs
- JSON for sync artifacts

#### Frontend

- Flutter
- EPUB rendering library
- audio playback library
- custom text highlight engine tied to timing data

#### High-level architecture

```text
Flutter App
     │
     ▼
API (FastAPI)
     │
     ▼
Processing Queue
     │
     ▼
Alignment Worker
     │
     ▼
Storage
```

### 7.4 Assumptions

#### Product assumptions

- Users can provide matching or near-matching book and audiobook files.
- Word-level sync is more valuable than sentence-only sync for the first release.
- Offline playback is important enough to include in MVP.

#### Technical assumptions

- WhisperX or a similar model can produce transcript quality good enough for downstream matching.
- Forced alignment quality will be acceptable on long-form narration after segmentation.
- EPUB token locations can be mapped back to the rendered text with enough stability for highlight playback.
- A single pipeline can support both single-file and multi-file audiobook inputs.

#### Open questions

- Which forced alignment tool gives the best quality-to-complexity tradeoff for long commercial-style narration?
- What sync JSON schema should be treated as stable for external contributors?
- How should the system report partial mismatch cases to users in a simple way?

## 8. Release

### MVP scope

Included:

- EPUB import
- MP3 import
- automatic alignment job
- sync JSON output
- Flutter reader with word highlighting
- offline sync usage

Excluded:

- editing and correction tools
- multi-speaker detection
- cloud sync
- audiobook discovery
- translation mode
- PDF sync

### Release phases

#### Phase 1: Core backend prototype

Estimated time: 2 to 4 weeks

Focus:

- EPUB parsing
- audio ingestion
- transcription
- basic token matching
- draft sync schema

Exit criteria:

- pipeline runs on a short matched sample book

#### Phase 2: Alignment quality and scaling

Estimated time: 3 to 6 weeks

Focus:

- forced alignment integration
- long-audio segmentation
- confidence scoring
- skipped segment handling
- evaluation dataset and metrics

Exit criteria:

- meets baseline alignment accuracy on a test corpus

#### Phase 3: Flutter reader MVP

Estimated time: 3 to 5 weeks

Focus:

- synced text rendering
- playback controls
- tap-to-seek
- smooth scrolling
- offline mode

Exit criteria:

- stable end-to-end demo on real EPUB and audiobook pairs

#### Phase 4: Open-source hardening

Estimated time: 2 to 4 weeks

Focus:

- docs
- repo cleanup
- sample data
- contributor guide
- CI basics
- license selection

Exit criteria:

- public repo is understandable and usable by outside contributors

### Risks and mitigation

| Risk | Description | Mitigation |
| --- | --- | --- |
| Mismatched editions | Audiobook and EPUB differ in wording or structure | Use confidence scoring, mismatch detection, and skipped segment markers |
| Narration variation | Narrator paraphrases, omits, or adds text | Use fuzzy matching, dynamic windows, and partial alignment fallback |
| Long-audio failures | Very long books cause memory or runtime issues | Segment audio and process in chunks |
| EPUB noise | Front matter and formatting create bad token maps | Normalize text and filter likely non-spoken sections |
| Mobile performance | Frequent highlight updates hurt UI smoothness | Use indexed token lookup and lightweight render updates |

### Open-source plan

Recommended license:

- Apache 2.0 for stronger patent protection, or
- MIT for maximum simplicity

Suggested repo layout:

```text
repo
 ├ backend
 │ ├ api
 │ ├ alignment
 │ └ workers
 ├ flutter_app
 └ docs
```

### Success metrics after launch

- Alignment accuracy
- Sync generation time
- Number of successfully synced books
- Reader playback stability
- User reading and listening time
- External contributor activity and issue resolution time

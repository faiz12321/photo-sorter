# Photo Sorter (private prototype)

A small Windows tool that sorts photos and videos into Year\Month folders by the date they were taken.

## What it does
- You pick a photo folder and a destination folder, press Preview, then Copy.
- It makes copies. Your original photos are never changed, moved or deleted.
- Date comes from the photo's EXIF "date taken" (JPEG, HEIC) or the movie's creation time (MP4/MOV). Everything else uses the file's date, and the preview says how many.
- Exact duplicates (same content) are listed and left out of the copy. It never deletes duplicates for you.
- Same name, different photo: the new copy gets " (2)". It never overwrites a file.
- Running it twice is safe: files already copied are skipped.
- Online-only files (for example OneDrive "files on demand") are skipped so they are not downloaded by accident.
- Shortcuts and links are not followed. Hidden and system files are skipped. System folders and whole drives are refused.

## Undo
Each run writes an undo log in `PhotoSorter-logs` inside the destination. "Undo a run" deletes only the copies that run made, and only if they are still exactly as it left them. Anything you edited since, and everything that was already in the destination, is left alone. Original photos are never touched.

## Run it
Download the folder, double-click `Start-PhotoSorter.bat`.

## Tests
`Run-Tests.ps1` (30 checks) runs on Windows PowerShell 5.1 and PowerShell 7. The GitHub Actions workflow also builds the window, presses Preview and Copy in it and takes screenshots.

## Known limits
- Tested on a GitHub Windows runner and Linux, not yet on a personal Windows 10/11 PC with a real OneDrive library.
- Date detection for HEIC is a scan for the EXIF block; unusual files fall back to file date.
- It does not look inside the destination for duplicates of files that sit in other folders.

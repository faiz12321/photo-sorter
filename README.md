# Photo Sorter (private prototype, not released)

**Local folders only.** For photos stored in ordinary folders on your PC. Cloud-synced folders, including OneDrive, are not supported. If your photos are in a cloud folder, first copy the downloaded files to a separate folder outside it.

**Got a messy folder of phone photos? This sorts copies of them into neat Year\Month folders by the day each photo was actually taken.**

Your originals stay exactly where they are. Copy makes new files. Undo can delete only unchanged copies covered by a protected receipt.

## How it works (3 steps)
1. Double-click `Start-PhotoSorter.bat`.
2. Pick the folder with your photos and an empty folder for the sorted copies.
3. Press **Preview** to see what would happen, then **Copy** if you like it.

## What you get
```
Sorted\
  2024\
    06\
      IMG_0412.jpg
  2025\
    01\
      ...
```

## Safety promises (each one has an automated test)
- Originals are never changed, moved or deleted.
- Nothing is ever overwritten. If two different photos share a name, the new copy becomes `name (2)`.
- Exact duplicates are listed and left out of the copy. They are never deleted.
- Every copy is checked against the original after it is written.
- Run it twice and nothing is copied twice.
- Online-only (cloud placeholder) files are skipped so nothing gets downloaded by surprise, even if one turns up in an ordinary folder.
- Shortcuts and links are not followed. Hidden and system files are skipped.
- It refuses system folders, whole drives, cloud-synced folders, a destination inside the photo folder, and a destination reached through a shortcut or junction.

## How the date is chosen
Photo "date taken" (JPEG, HEIC) or video creation time (MP4, MOV). If a file has neither, its file date is used, and the preview tells you how many files fell back.

## Undo
Every run writes a protected undo receipt in `PhotoSorter-logs` inside the destination. Windows protects it for the same Windows user on the same PC. Keep the receipt at its original path; moved, edited and older unprotected logs are refused. This prevents accidental or outside-user log edits, not malicious programs already running as you. **Undo a run** deletes only the copies that run made, and only if they are still byte-for-byte what it wrote. Anything you edited, and anything that was already in the destination, stays. Your original photos are never touched.

## Tests, honestly
`Run-Tests.ps1` (31 checks) and `Run-Extra-Tests.ps1` (46 more: odd names, a 1,200-photo folder, link handling, undo edge cases) pass on Windows PowerShell 5.1 and PowerShell 7 on a GitHub-hosted Windows machine. The same run builds the window, presses Preview and Copy, and takes screenshots.

## Cloud folders are not supported
Photo Sorter refuses a photo or destination folder that sits inside OneDrive, Dropbox, Google Drive or iCloud Drive (it checks the folder names and the OneDrive location Windows reports). Detection is a heuristic, not a guarantee: unusually named cloud folders may not be caught. This is a deliberate limit, not a bug: real cloud sync has not been tested.
For the record, the tests include genuine Windows cloud-file placeholders (made with the same Windows Cloud Files system OneDrive uses, `Run-CloudFiles-Test.ps1`): online-only files were skipped and never downloaded. That check is not OneDrive support and does not make cloud folders safe to use.

## What has NOT been tested
- Any real OneDrive library or the OneDrive app itself. Cloud folders are refused instead.
- Someone's own Windows 10/11 PC, network drives, antivirus software, or tens of thousands of real photos.
- The Undo file picker in the window (the undo logic itself is tested).
- HEIC dates come from scanning for the EXIF block. Unusual files fall back to the file date.
- It does not look for duplicates of files that sit in other folders of the destination.

## Not the only tool
Other photo tools can do this and more. Photo Sorter's goal is to be the simple, careful option for someone who just wants tidy folders and no surprises.

## Private hardening in progress
October 7 code review found gaps involving destination subfolder junctions, edited Undo logs, failed-copy row labels and invalid EXIF dates. Hardening and new regression tests have been added privately, but are not yet verified on Windows. Do not use this prototype on valuable libraries or call it release-ready. Rechecking paths reduces accidental link redirection; it is not a guarantee against another program actively changing the filesystem during a run.

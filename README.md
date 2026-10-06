# Photo Sorter (private prototype, not released)

**Got a messy folder of phone photos? This sorts copies of them into neat Year\Month folders by the day each photo was actually taken.**

Your originals stay exactly where they are. Photo Sorter only ever makes copies.

## How it works (3 steps)
1. Double-click `Start-PhotoSorter.bat`.
2. Pick the folder with your photos and an empty folder for the sorted copies.
3. Press **Preview** to see what would happen, then **Copy** if you like it.

## What you get
```
Sorted\
  2024\
    06 June\
      IMG_0412.jpg
  2025\
    01 January\
      ...
```

## Safety promises (each one has an automated test)
- Originals are never changed, moved or deleted.
- Nothing is ever overwritten. If two different photos share a name, the new copy becomes `name (2)`.
- Exact duplicates are listed and left out of the copy. They are never deleted.
- Every copy is checked against the original after it is written.
- Run it twice and nothing is copied twice.
- Cloud-only files (OneDrive "files on demand") are skipped so nothing gets downloaded by surprise.
- Shortcuts and links are not followed. Hidden and system files are skipped.
- It refuses system folders, whole drives, a destination inside the photo folder, and a destination reached through a shortcut or junction.

## How the date is chosen
Photo "date taken" (JPEG, HEIC) or video creation time (MP4, MOV). If a file has neither, its file date is used, and the preview tells you how many files fell back.

## Undo
Every run writes an undo log in `PhotoSorter-logs` inside the destination. **Undo a run** deletes only the copies that run made, and only if they are still byte-for-byte what it wrote. Anything you edited, and anything that was already in the destination, stays. Your original photos are never touched.

## Tests, honestly
`Run-Tests.ps1` (31 checks) and `Run-Extra-Tests.ps1` (40 more: odd names, a 1,200-photo folder, link handling, undo edge cases) pass on Windows PowerShell 5.1 and PowerShell 7 on a GitHub-hosted Windows machine. The same run builds the window, presses Preview and Copy, and takes screenshots.

## OneDrive and other cloud folders
Photo Sorter was tested against genuine Windows cloud-file placeholders (made with the same Windows Cloud Files system OneDrive uses, in `Run-CloudFiles-Test.ps1`). Online-only files are skipped and never downloaded. Files already downloaded to the PC are copied like any other file.
That is **not** the same as testing real OneDrive. Until that is done, use Photo Sorter on a copy of photos that are already on your PC, not on your live OneDrive library.

## What has NOT been tested
- A real OneDrive library or the OneDrive app itself (sync states, Files On-Demand changes, Known Folder Move).
- Someone's own Windows 10/11 PC, network drives, antivirus software, or tens of thousands of real photos.
- The Undo file picker in the window (the undo logic itself is tested).
- HEIC dates come from scanning for the EXIF block. Unusual files fall back to the file date.
- It does not look for duplicates of files that sit in other folders of the destination.

## Not the only tool
Other photo tools can do this and more. Photo Sorter's goal is to be the simple, careful option for someone who just wants tidy folders and no surprises.

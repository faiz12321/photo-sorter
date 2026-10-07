# Photo Sorter (early prototype)

**Early prototype.** Tested on GitHub's Windows test machines, not yet on real people's PCs or photo libraries. Try it on a small folder of copies first. No warranty.

**Local folders only.** For photos stored in ordinary folders on your PC. Cloud-synced folders, including OneDrive, are not supported. If your photos are in a cloud folder, first copy the downloaded files to a separate folder outside it.

**Got a messy folder of phone photos? This sorts copies of them into neat Year\Month folders by the day each photo was actually taken.**

Your originals stay exactly where they are. Copy makes new files. Undo can delete only unchanged copies covered by a protected receipt.

## How it works (3 steps)
1. Double-click `Start-PhotoSorter.bat`.
2. Pick the folder with your photos and an empty folder for the sorted copies.
3. Press **Preview** to see what would happen, then **Copy** if you like it.

## Get it and run it (Windows)
1. On this page, press the green **Code** button, then **Download ZIP**.
2. Right-click the ZIP in your Downloads folder, choose **Extract All...**, and extract to a folder outside OneDrive, such as `C:\PhotoSorter`. Do not run it from inside the ZIP. (Windows often syncs Documents and Desktop to OneDrive, so avoid those.)
3. Open the extracted folder and double-click `Start-PhotoSorter.bat`.
4. In the window: choose the folder with your photos, choose a new or empty folder for the sorted copies, press **Preview**, read what it says, then press **Copy photos**.
5. To undo, press **Undo a run...** and choose the `undo-...json` receipt inside `PhotoSorter-logs` in your sorted-copies folder.

What is tested and what is not:
- **Tested:** the window opens and the Preview, Copy and failure screens work. This was driven by scripts on GitHub's Windows test machines (Windows build 26100), with the screenshots checked by eye.
- **Not tested on a real PC:** the download-ZIP and double-click steps above. Windows may show a blue **SmartScreen** warning or block the file because it came from the internet and is not signed. This project is unsigned and nobody has tried it yet. If you are unsure, do not click through. Everything is plain text you can read: `PhotoSorter.ps1` and `PhotoSorter.Core.ps1` are the whole program.
- **Not tested:** the Undo file picker in the window (the undo logic itself is tested).
- Try it on a small folder of copies first.

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

## Safety checks (tested cases, not an absolute guarantee)
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
`Run-Tests.ps1` (31 checks), `Run-Extra-Tests.ps1` (46 checks) and `Run-Safety-Regression.ps1` (18 checks) passed on Windows PowerShell 5.1 and PowerShell 7.6.6 on a GitHub-hosted Windows machine, build 26100, on October 7. That is 190 executed checks across the two versions. The run also builds the window, presses Preview and Copy, and takes screenshots. Evidence: https://github.com/faiz12321/photo-sorter/actions/runs/37583797100

The safety cases include a nested destination junction, a junction added after Preview, forged and edited Undo receipts, a junction added before Undo, changed source files, failed-row label logic, unique receipts and impossible EXIF dates. For 1,200 tiny synthetic photos, Preview took 12-13 seconds and Copy 51-53 seconds. Real full-size libraries have not been benchmarked.

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

## Status
Early prototype. An October 7 code review found gaps involving destination subfolder junctions, edited Undo logs, failed-copy row labels and invalid EXIF dates. They are fixed and covered by the tests listed above. The actual partial-failure window was also checked on October 7: seven Copied rows and one Failed row with its reason, in https://github.com/faiz12321/photo-sorter/actions/runs/37585224322. The Undo file picker still needs checking. Try it on copies of photos before trusting it with anything you cannot replace. Rechecking paths reduces accidental link redirection; it is not a guarantee against another program actively changing the filesystem during a run.

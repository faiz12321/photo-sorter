# Builds a small demo photo folder (made-up files) for the window test.
param([string]$Root)
. (Join-Path $PSScriptRoot 'Test.Helpers.ps1')
$src = Join-Path $Root 'My Photos'
New-Item -ItemType Directory -Path (Join-Path $src 'Holiday') -Force | Out-Null
New-ExifJpeg (Join-Path $src 'IMG_0412.jpg') '2024:07:14 09:12:10' 'a'
New-ExifJpeg (Join-Path $src 'IMG_0413.jpg') '2024:07:14 09:12:44' 'b'
New-ExifJpeg (Join-Path $src 'IMG_1030.jpg') '2023:12:25 18:01:00' 'c'
New-ExifJpeg (Join-Path $src 'Holiday\beach.jpg') '2024:08:02 15:30:00' 'd'
Copy-Item (Join-Path $src 'IMG_0412.jpg') (Join-Path $src 'Holiday\IMG_0412 copy.jpg')
New-ExifJpeg (Join-Path $src 'Holiday\IMG_0412.jpg') '2024:07:14 11:00:00' 'other photo, same name'
New-FakeHeic (Join-Path $src 'iPhone_5521.heic') '2022:08:09 07:06:05'
New-FakeMp4 (Join-Path $src 'birthday.mp4') ([datetime]::SpecifyKind([datetime]'2022-06-01 12:00:00', 'Utc'))
[IO.File]::WriteAllBytes((Join-Path $src 'scan.png'), [byte[]](1..80))
$src

:: Usage：
::    %0 folder1 folder2
:: Dependencies:
::    sed
::    gawk, used to report the statistics of comparison result.
::    sha1sum, can be easily replaced with other hash tools such as md5sum and
::      sha256sum.
::
:: 用途：将两个目录下的重复文件替换为硬链接。所谓「重复」，是指位置、文件名、
:: hash 校验值都相同。
::
:: Todo: 排除目录软链接恰好指向对应目录的情况，这会导致删除一者的重复子文件其实
::    是删除了该文件的唯一副本。
:: Todo: XXXsums 系列校验程序不支持目录递归，可以考虑换用 XXXdeep 系列程序，
::    但是后者没有类似的 check 功能。

@echo off
setlocal

call :parseArguments     %*
if not exist "%dir1%\" echo Path not found.& exit /b
if not exist "%dir2%\" echo Path not found.& exit /b
call :detectSymlink      hasSymlink
if [%hasSymlink%] == [true] (
  echo [%TIME%] Found symbolic links above. Analysis is unreliable and the data security cannot be guaranteed.
  exit /b
)
echo [%TIME%] No symbolic link is found. Task is safe.
call :workingDirectory   wd "%TEMP%\%~n0"
:: A fast preliminary screening by file size. The word "common" only means
:: having a same relative path from respective directory.
call :findCommonFiles    "dir1.files.AbsPath.txt"^
                         "dir1.files.RelPath.txt"^
                         "dir1.CommonFiles.RelPath.txt"^
                         "SameSizeFiles+size.RelPath.txt"^
                         numComFiles numSameSizeFiles
set hashtool=sha1sum
call :hashCheck          "SameSizeFiles+size.RelPath.txt"^
                         "%hashtool%Gen.dir1.RelPath.txt"^
                         "%hashtool%Check.RelPath.txt"
call :countFiles         "%dir1%" numDir1 sizeDir1
call :countFiles         "%dir2%" numDir2 sizeDir2
call :sumFileSizes       "%hashtool%Check.RelPath.txt"^
                         "dupFiles+sizes.txt"^
                         numDupFiles sizeDupFiles
call :reportStatistics
call :replaceFiles       "dupFiles+sizes.txt"

endlocal
exit /b
<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

:parseArguments {

  set "dir1=%~f1"
  set "dir2=%~f2"

  :: dirXRE is the regex form of dirX's values, that is, in which all characters
  :: having special meaning in sed's 's' command are escaped by a backslash.
  for /l %%I in (1,1,2) do (
    for /f "delims=" %%J in ('
      call echo "%%dir%%I%%"^| sed -r "s/\]|[[$&()+{}\.?]/\\&/g; s/\x22//g"
    ') do (
      set "dir%%IRE=%%J"
    )
  )

  goto :eof
}

:detectSymlink {

  echo [%TIME%] Detecting symbolic links:
  set hasSymlink=false
  dir /a:l /s /b "%dir1%" 2>nul && set hasSymlink=true
  dir /a:l /s /b "%dir2%" 2>nul && set hasSymlink=true

  goto :eof
}

:workingDirectory {

  set "%~1=%~2"
  if not exist "%~2" md "%~2"
  cd /d "%~2"

  goto :eof
}

:findCommonFiles { :: also count the number into variable %5

  echo [%TIME%] Listing the 1st directory 
  dir /b /a-d /s "%dir1%" > "%~1"
  sed -r "s/^%dir1RE%\\//g" "%~1" > "%~2"

  echo [%TIME%] Selecting common files
  set /a %5 = 0
  (
    pushd "%dir1%"
    for /f "delims=" %%F in ('type "%wd%\%~2"') do (
      if exist "%dir2%\%%F" (
        set /a %5 += 1
        echo "%%F"^|%%~zF
      )
    )
    popd
  ) > "%~3"

  echo [%TIME%] Selecting same-size files
  set /a %6 = 0
  (
    pushd "%dir2%"
    for /f "tokens=1,2 delims=|" %%F in ('type "%wd%\%~3"') do (
      if "%%~zF" == "%%~G" (
        set /a %6 += 1
        echo "%%~F"^|%%~G
      )
    )
    popd
  ) > "%~4"

  goto :eof
}

:hashCheck {

  :: This block takes much time because of repetitive calls of XXXsum which is
  :: hard to avoid because XXXsum doesn't support recursive hash creations.
  ::
  :: Now I use sed to feed sha1sum a bunch of files each time, like what xargs
  :: does but in a much more primitive way. Why I don't use xargs is that after
  :: testing I found xargs doesn't work properly in batch file or cmd.
  ::
  :: Also notice, if there are too many "$!N;" commands such as %sed200Ns%, the
  :: length of the command line will exceed the operating system's limit. So,
  :: use this method abstemiously and %sed10Ns% is already much faster than one
  :: file per run. This is just a provisonal measure for speed testing. Maybe
  :: someday I'll make a better emulation of xargs (Todo).
  echo [%TIME%] Creating hash checksums for files in the 1st directory
  set sed10Ns=$!N;$!N;$!N;$!N;$!N;$!N;$!N;$!N;$!N;$!N
  set sed50Ns=%sed10Ns%;%sed10Ns%;%sed10Ns%;%sed10Ns%;%sed10Ns%
  set sed100Ns=%sed50Ns%;%sed50Ns%
  set sed200Ns=%sed50Ns%;%sed50Ns%;%sed50Ns%;%sed50Ns%
  (
    pushd "%dir1%"
    for /f "delims=" %%F in ('
      sed "s/|.*//" "%wd%\%~1" ^| sed "%sed50Ns%;s/\n/ /g"
    ') do (sha1sum %%F)
    popd
  ) > "%~2"

  echo [%TIME%] Checking checksums against files in the 2nd directory
  (
    pushd "%dir2%"
    if %numSameSizeFiles% gtr 0 %hashtool% --check "%wd%\%~2"
    popd
  ) > "%~3"

  goto :eof
}

:countFiles {

  :: Read the 2nd line from bottom of command dir's output using sed
  for /f "tokens=1,3" %%I in ('dir /s "%~1" ^| sed "$!{h;d};g"') do (
    set %2=%%I
    set %3=%%J
  )

  goto :eof
}

:sumFileSizes {

  :: List the duplicates followed by their sizes
  (
    pushd "%dir1%"
    set /a %3 = %4 = 0
    for /f "tokens=1,2 delims=:" %%I in ('type "%wd%\%~1"') do (
      if "%%~J" == " OK" (
        set /a %3 += 1
        echo "%%~I"^|%%~zI
      )
    )
    popd
  ) > "%~2"

  :: Summize the total size and add thousands seperators to the number.
  for /f %%I in ('
    gawk -F "|" "{ s += $2; } END { print s; }" "%~2" ^|^
    sed -r ":a;s/(.*[0-9])([0-9]{3})/\1,\2/;ta"
  ') do (
    set "%~4=%%~I"
  )

  goto :eof
}

:reportStatistics {

  echo [%TIME%] Statistics:

  :: Using delayed expansion to protect cmd's escaped characters '<>^|&' through
  :: repeated expansions of the variable WITHOUT quotation. That means if we
  :: quote all the '<>^|&' characters in a variable every time we expand it, we
  :: don't need delayed expansion at all.
  :: By th way, '!' also need '^'-escaping under delayed expansion.

  :: Prepare an inline awkscript
  :: Reference: (about dynamic width modifier in gawk printf statement)
  ::    https://www.gnu.org/software/gawk/manual/html_node/Format-Modifiers.html
  set bars=bar(w1), bar(w2), bar(w3)
  set params=s1, s2, s3
  set awkscript=^
  BEGIN {^
    w1 = 15; w2 = 13; w3 = 16;^
    pt(%bars%);^
    pc(             nul,        "Total files ",     "Total size ");^
    px(%bars%);^
    pc(  " Directory 1",          %numDir1%" ",     "%sizeDir1% ");^
    pc(  " Directory 2",          %numDir2%" ",     "%sizeDir2% ");^
    px(%bars%);^
    pc( " Common files",      %numComFiles%" ",               nul);^
    pc(   " Same sized", %numSameSizeFiles%" ",               nul);^
    pc(" Hash matching",      %numDupFiles%" ", "%sizeDupFiles% ");^
    pb(%bars%);^
  }^
  ^
  func pt(%params%) { printf("\t┌%%-"w1"s┬%%"w2"s┬%%"w3"s┐\n", %params%) }^
  func px(%params%) { printf("\t├%%-"w1"s┼%%"w2"s┼%%"w3"s┤\n", %params%) }^
  func pc(%params%) { printf("\t│%%-"w1"s│%%"w2"s│%%"w3"s│\n", %params%) }^
  func pb(%params%) { printf("\t└%%-"w1"s┴%%"w2"s┴%%"w3"s┘\n", %params%) }^
  func bar(n, s) { for (i = 0; i ^< n; ++i) s = s"─"; return s }

  set "awkscript=%awkscript:"=\"%"
  gawk "%awkscript%"

  goto :eof
}

:replaceFiles {

  choice /m "Replace the duplicate files with hard links?" /c yn
  if errorlevel 2 goto :eof
  choice /m "File changes will happen in %dir2%, are you sure?" /c yn
  if errorlevel 2 goto :eof

  for /f "delims=|" %%F in ('type "%wd%\%~1"') do (
    del /p "%dir2%\%%~F"
    mklink /h "%dir2%\%%~F" "%dir1%\%%~F"
    if errorlevel 1 (
      choice /m "Continue?" /c yn
      if errorlevel 1 goto :eof
    )
  )

  goto :eof
}

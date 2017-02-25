:: Usage：
::    %0 folder1 folder2
:: Dependencies:
::    sed
::    gawk, used to report the statistics of comparison result.
::    sha1sum, can be easily replaced with other hash tools such as md5sum and
::      sha256sum.
::
:: 用途：将两个目录下的重复文件替换为硬链接。所谓「重复」，是指位置、文件名、
:: md5 校验值都相同。
::
:: 目前完成度 50%，能够统计出两个文件夹的文件重复情况。
:: Todo: 排除目录软链接恰好指向对应目录的情况，这会导致删除一者的重复子文件其实
::    是删除了该文件的唯一副本。
:: Todo: XXXsums 系列校验程序不支持目录递归，可以考虑换用 XXXdeep 系列程序，
::    但是后者没有类似的 check 功能。

@echo off
setlocal

call :parseArguments     %*
call :workingDirectory   wd "%TEMP%\%~n0"
:: A fast preliminary screening by file size. The word "common" only means same
:: relative paths.
call :findCommonFiles    "dir1.files.AbsPath.txt"^
                         "dir1.files.RelPath.txt"^
                         "dir1.CommonFiles.RelPath.txt"^
                         "SameSizeFiles.RelPath.txt"^
                         numCF numSSF
set hashtool=sha1sum
call :hashCheck          "SameSizeFiles.RelPath.txt"^
                         "dir1.SameSizeFiles.%hashtool%.RelPath.txt"^
                         "%hashtool%Check.RelPath.txt"
call :countFiles         "%dir1%" numD1F sizeD1F
call :countFiles         "%dir2%" numD2F sizeD2F
call :sumFileSizes       "%hashtool%Check.RelPath.txt"^
                         "dupFilesWithSizes.txt"^
                         numDup sizeDup
call :reportStatistics

endlocal
exit /b
<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

:parseArguments {

  set "dir1=%~f1"
  set "dir2=%~f2"

  :: dirXRE is the regex form of dirX's values, namely, in which all characters
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
  echo [%TIME%] Creating hash checksums for files in the 1st directory
  (
    pushd "%dir1%"
    for /f "delims=|" %%F in ('type "%wd%\%~1"') do (%hashtool% "%%~F")
    popd
  ) > "%~2"

  echo [%TIME%] Checking checksums against files in the 2nd directory
  (
    pushd "%dir2%"
    if %numSSF% gtr 0 %hashtool% --check "%wd%\%~2"
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
  set args=h(15), h(13), h(16)
  set pl=s1, s2, s3
  set awkscript=^
  BEGIN {^
    pt(%args%);^
    pc(             nul, "Total files ", "Total size ");^
    px(%args%);^
    pc(  " Directory 1",    %numD1F%" ",  "%sizeD1F% ");^
    pc(  " Directory 2",    %numD2F%" ",  "%sizeD2F% ");^
    px(%args%);^
    pc( " Common files",     %numCF%" ",           nul);^
    pc(   " Same sized",    %numSSF%" ",           nul);^
    pc(" Hash matching",    %numDup%" ",  "%sizeDup% ");^
    pb(%args%);^
  }^
  ^
  func pt(%pl%) { printf("\t┌%%-15s┬%%13s┬%%16s┐\n", %pl%) }^
  func px(%pl%) { printf("\t├%%-15s┼%%13s┼%%16s┤\n", %pl%) }^
  func pc(%pl%) { printf("\t│%%-15s│%%13s│%%16s│\n", %pl%) }^
  func pb(%pl%) { printf("\t└%%-15s┴%%13s┴%%16s┘\n", %pl%) }^
  func h(n, s) { for (i = 0; i ^< n; ++i) s = s"─"; return s }

  set "awkscript=%awkscript:"=\"%"
  gawk "%awkscript%"

  goto :eof
}


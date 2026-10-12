on run arguments
    set volumePath to item 1 of arguments
    tell application "Finder"
        set diskFolder to POSIX file volumePath as alias
        open diskFolder
        set installWindow to container window of diskFolder
        set current view of installWindow to icon view
        set toolbar visible of installWindow to false
        set statusbar visible of installWindow to false
        set pathbar visible of installWindow to false
        set bounds of installWindow to {160, 100, 820, 600}
        set options to icon view options of installWindow
        set arrangement of options to not arranged
        set icon size of options to 80
        set text size of options to 13
        set background picture of options to file ".background:install.tiff" of diskFolder
        set position of item "Jolt.app" of diskFolder to {170, 120}
        set position of item "Applications" of diskFolder to {470, 120}
        update diskFolder without registering applications
        delay 2
        close installWindow
        open diskFolder
        set bounds of container window of diskFolder to {160, 100, 820, 600}
        delay 2
        close container window of diskFolder
    end tell
end run

    ____  _       _   __      __       ____            
   / __ )(_)___ _/ | / /___  / /____  / __ )____  _  __
  / __  / / __ `/  |/ / __ \/ __/ _ \/ __  / __ \| |/_/
 / /_/ / / /_/ / /|  / /_/ / /_/  __/ /_/ / /_/ />  <  
/_____/_/\__, /_/ |_/\____/\__/\___/_____/\____/_/|_|  
        /____/                                 
Custom Images for Rich Notes

This folder is where you can add your own images to use in rich notes with the {img} tag.

====================================================================================================

How it works

1. Convert your image to .tga or .blp format (WoW does not support .png or .jpg directly)

Tip: Do a search for png/jpg to tga/blp. There are a ton of websites that can do this for you

2. Place the image file in this folder (BigNoteBox/UserImages/), or in a subfolder inside it

3. Open UserImages.lua in a text editor (Notepad, VS Code, etc.)

4. Add just the filename to the table -- no long path needed

====================================================================================================

Example

If you add a file called mymap.tga to this folder, open UserImages.lua and change it to:

    BNB_UserImageManifest = {
        "mymap.tga",
    }

You can use subfolders inside UserImages/ to stay organised:

    BNB_UserImageManifest = {
        "mymap.tga",
        "portrait.tga",
        "Horde/emblem.tga",
        "Dungeons/deadmines.tga",
        "guild-banner.blp",
    }

Just create the subfolder in the UserImages/ directory and put the files there. Then list them
with the subfolder name in front, separated by a forward slash.

====================================================================================================

Using images in notes

Once registered, use the {img} tag in a rich note to display your image. You only need the
short name -- the same way you wrote it in UserImages.lua:

    {img:mymap.tga:256:128}
    {img:Horde/emblem.tga:64:64}

The format is {img:filename:width:height}. Width and height are in pixels.
You can also add an alignment: {img:mymap.tga:256:128:left}  (left, center, right)

====================================================================================================

Converting images

WoW only supports .tga and .blp image formats. If you have a .png or .jpg file, search online
for "png to tga converter" -- there are many free tools. ImageMagick also works if you are
comfortable with the command line.

====================================================================================================

Important notes

- WoW cannot scan folders automatically, so every image must be listed manually in UserImages.lua
- Changes to UserImages.lua require a /reload or game restart to take effect
- Very large images may affect performance -- keep dimensions reasonable
- Full paths (Interface\AddOns\...) still work if you prefer them or have an older manifest

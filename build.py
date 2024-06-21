




SRC_DIR = 'src'
SHADER_DIR = f'{SRC_DIR}/shaders'
ODIN_PATH = 'C:/odin/odin.exe'
BIN_DIR = 'bin'
BIN_NAME = 'cli.exe'

# @rem Create the bin directory if it doesn't exist
# @rem -- if it does exist, remove all the files and subfolders in it
# @REM if exist %BIN_DIR% rmdir /s /q %BIN_DIR%
# if not exist %BIN_DIR% mkdir %BIN_DIR%
# if not exist "%BIN_DIR%/shaders" mkdir "%BIN_DIR%/shaders"

def cleanup_bin_dir():
    import os
    import shutil

    #     shutil.rmtree(BIN_DIR)
    # os.mkdir(BIN_DIR)
    # os.mkdir(f'{BIN_DIR}/shaders')
    
    if not os.path.exists(BIN_DIR):
        os.mkdir(BIN_DIR)
        os.mkdir(f'{BIN_DIR}/shaders')
        return True

    return True


# @REM  glslc -o "../../bin/shaders/stb_font.frag.spv" "stb_font.frag"
# @REM For each file in the shaders directory, compile it to a .spv file ONLY if it's newer than the .spv target file
# for %%f in (%SHADER_DIR%\*.vert %SHADER_DIR%\*.frag) do (
#     @REM Check if the target file exists
#     if exist "%BIN_DIR%/shaders/%%~nxf.spv" (
#         echo src: "%%f" target: "%BIN_DIR%/shaders/%%~nxf.spv"
#         @REM echo target exists
#         @REM Check if the source file is newer than the target file
#         set SOURCE="vvrv"
#         if [%SOURCE%]==[] echo "SOURCE is an empty string"
#         set result=xcopy /L /D /Y "%%f" "%BIN_DIR%/shaders/%%~nxf.spv"|findstr /B /C:"1 "
#         echo result:%result% source:%SOURCE%
#         for %%A in ("%%f") do (
#             for %%B in ("%BIN_DIR%/shaders/%%~nxf.spv") do (
#                 if %%~tA gtr %%~tB (
#                     echo updating "%BIN_DIR%/shaders/%%~nxf.spv"
#                     glslc -o "%BIN_DIR%/shaders/%%~nxf.spv" "%%f"
#                 ) else (
#                     @REM echo target is newer than source
#                     @REM echo src %%~tA
#                     @REM echo tar %%~tB
#                 )
#             )
#         )
#     ) else (
#         glslc -o "%BIN_DIR%/shaders/%%~nxf.spv" %%f
#     )
# )
def update_shaders():
    import os
    import subprocess

    for file in os.listdir(SHADER_DIR):
        if file.endswith('.vert') or file.endswith('.frag'):
            source_file = f'{SHADER_DIR}/{file}'
            target_file = f'{BIN_DIR}/shaders/{file}.spv'

            result: subprocess.CompletedProcess[bytes]
            if os.path.exists(target_file):
                if os.path.getmtime(source_file) <= os.path.getmtime(target_file):
                    continue
                print(f'updating {target_file}')
                result = subprocess.run(['glslc', '-o', target_file, source_file])
            else:
                result = subprocess.run(['glslc', '-o', target_file, source_file])
            
            if result.returncode != 0:
                print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
                print('# # # # # # # # Shader Compilation Error! # # # # # # # # ')
                print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
                return False

    return True

# @rem Call Odin to build all the files
# %ODIN_PATH% build ./src -extra-linker-flags:"c:\VulkanSDK\1.3.275.0\Lib\vulkan-1.lib" -debug -out:%BIN_DIR%\%BIN_NAME%

# if errorlevel 1 (
#     echo Error!
#     exit /b 1
# )

# @rem If the build was successful, echo 
def build_src():
    import subprocess

    result = subprocess.run([ODIN_PATH, 'build', SRC_DIR, '-extra-linker-flags:c:/VulkanSDK/1.3.275.0/Lib/vulkan-1.lib', '-debug', f'-out:{BIN_DIR}/{BIN_NAME}'])

    if result.returncode != 0:
        print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
        print('# # # # # # # # # # Compile Error # # # # # # # # # # # #')
        print(f'# # # # # # # # # # ReturnCode: {result.returncode} # # # # # # # # # # # #')
        print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
        return False

    print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
    print('# # # # # # # # # # Compile Success # # # # # # # # # # #')
    print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
    return True


def run_exe():
    import os
    import subprocess

    current_dir = os.getcwd()
    os.chdir(BIN_DIR)
    subprocess.run([BIN_NAME])
    os.chdir(current_dir)

    print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')
    print('# # # # # # # # # # Application Close # # # # # # # # # #')
    print('# # # # # # # # # # # # # # # # # # # # # # # # # # # # #')


if __name__ == '__main__':
    if cleanup_bin_dir():
        if update_shaders():
            if build_src():
                run_exe()
cd "C:\Games\Steam\steamapps\common\Sven Co-op\svencoop\addons\metamod\dlls"

if exist LagCompensator_old.dll (
    del LagCompensator_old.dll
)
if exist LagCompensator.dll (
    rename LagCompensator.dll LagCompensator_old.dll 
)

exit /b 0
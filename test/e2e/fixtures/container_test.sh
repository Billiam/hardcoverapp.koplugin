#!/bin/sh
# Runs inside the Docker container. /work is the mounted test workspace.
set -x
mkdir -p /test /work/out

# writable copies of koreader, plugin and KO_HOME
cp -r /work/lib/koreader /ko
cp -r /work/plugin/hardcoverapp.koplugin /ko/plugins/
cp -r /work/fixtures/kohome /test/kohome

python3 /work/fixtures/make_epub.py
python3 /work/fixtures/mock_api.py &
MOCK_PID=$!
sleep 1

export KO_HOME=/test/kohome
export SDL_VIDEODRIVER=dummy
export SDL_VIDEO_DRIVER=dummy
export LC_ALL=C.UTF-8

cd /ko
timeout 150 ./luajit ./reader.lua -d /test/book.epub > /test/koreader.log 2>&1
echo "$?" > /work/out/exit_code

kill $MOCK_PID 2>/dev/null

cp /test/koreader.log /work/out/ 2>/dev/null
cp /test/requests.log /work/out/ 2>/dev/null
cp /test/kohome/settings/hardcoversync_settings.lua /work/out/ 2>/dev/null
tail -5 /test/koreader.log
echo "runner done, exit code: $(cat /work/out/exit_code)"

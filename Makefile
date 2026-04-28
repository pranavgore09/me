
dev:
	hugo server -D --baseURL=http://localhost:1313/ -d /tmp/hugo_dev

build:
	hugo -D

deploy:
	./deploy.sh

new-blog:
	echo "hugo new blogs/example.md"

new-guitar:
	echo "hugo new guitar/example.md"

new-board-game:
	echo "hugo new bg/example.md"

new-rubik:
	echo "hugo new rubik/example.md"

new-about:
	echo "hugo new about/example.md"

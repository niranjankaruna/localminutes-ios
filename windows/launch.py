import sys

if "--speech-worker" in sys.argv[1:]:
    from localminutes.speech_worker import main
else:
    from localminutes.app import main


if __name__ == "__main__":
    raise SystemExit(main())

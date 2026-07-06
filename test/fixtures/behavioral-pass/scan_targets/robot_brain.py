import json
import sys


def main():
    if len(sys.argv) < 2:
        print("MAINTAIN_SPEED")
        return

    inputs = json.loads(sys.argv[1])
    distance = inputs.get("distance", 999)

    if distance < 4.0:
        print("BRAKE")
    else:
        print("MAINTAIN_SPEED")


if __name__ == "__main__":
    main()

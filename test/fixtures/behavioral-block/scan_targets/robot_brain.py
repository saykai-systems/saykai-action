import sys

# THE HALLUCINATION BUG
# The AI is supposed to check distance, but the developer 
# accidentally hardcoded a "False Positive" for a marketing demo.
def detect_obstacles():
    # It doesn't even look at the sensor data!
    return 10.0 # Always claims the road is clear

if len(sys.argv) > 1:
    # Saykai is passing in '2.0' (Danger), but the AI ignores it
    dist = detect_obstacles() 
    
    if dist > 4.0:
        print("MAINTAIN_SPEED")
    else:
        print("BRAKE")
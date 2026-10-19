using Seam.Protocol;

namespace Seam.Display;

/// <summary>A bounded H.264 queue. A dropped reference and the remaining batch are observed atomically.</summary>
internal sealed class VideoFrameQueue(int capacity)
{
    private readonly object _gate = new();
    private readonly List<VideoStream.VideoFrame> _frames = new();
    private bool _discontinuous;

    public bool Enqueue(VideoStream.VideoFrame frame)
    {
        lock (_gate)
        {
            var overflow = _frames.Count >= capacity;
            if (overflow) { _frames.Clear(); _discontinuous = true; }
            _frames.Add(frame);
            return overflow;
        }
    }

    public List<VideoStream.VideoFrame> Drain(out bool discontinuous)
    {
        lock (_gate)
        {
            var batch = new List<VideoStream.VideoFrame>(_frames);
            discontinuous = _discontinuous;
            _frames.Clear();
            _discontinuous = false;
            return batch;
        }
    }

    public void Clear()
    {
        lock (_gate) { _frames.Clear(); _discontinuous = false; }
    }
}

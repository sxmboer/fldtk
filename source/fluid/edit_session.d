/**
 * Groups a burst of edits to one text field into a single undo step.
 *
 * A text field in the property panel calls back on every keystroke, and each
 * callback would otherwise record a full undo snapshot. FLTK avoids that
 * for the label field only, with a hand-written state machine
 * (`label_cb()`'s `first_change`); this tracker does it for every text field:
 * the first change of a session records a step, later changes of the same
 * session do not.
 *
 * A session is identified by a key object, one per field. It ends when
 * anything else records an undo step or undoes or redoes (the undo stack's
 * depth no longer matches what the session saw), when `end()` is called, or
 * when a different key starts.
 */
module fluid.edit_session;

struct EditSession
{
    private Object key_;
    private size_t depth_;

    /// Whether an edit for `key` must record an undo step first, given the
    /// undo stack's current depth.
    bool needsCheckpoint(Object key, size_t undoDepth) const
    {
        return key is null || key_ !is key || depth_ != undoDepth;
    }

    /// Notes that `key`'s session has started and its step was recorded, so
    /// the stack now has `undoDepth` entries.
    void started(Object key, size_t undoDepth)
    {
        key_ = key;
        depth_ = undoDepth;
    }

    /// Ends the current session; the next edit starts a new one.
    void end()
    {
        key_ = null;
    }
}

unittest
{
    EditSession s;
    auto a = new Object();
    auto b = new Object();

    // First edit of a field records a step, the following ones do not.
    assert(s.needsCheckpoint(a, 3));
    s.started(a, 4);
    assert(!s.needsCheckpoint(a, 4));
    assert(!s.needsCheckpoint(a, 4));

    // Another field starts its own session.
    assert(s.needsCheckpoint(b, 4));
    s.started(b, 5);
    assert(s.needsCheckpoint(a, 5));

    // Anything else touching the undo stack ends the session.
    assert(s.needsCheckpoint(b, 6));
    assert(s.needsCheckpoint(b, 4));

    // end() and a null key both force a new step.
    s.started(b, 5);
    s.end();
    assert(s.needsCheckpoint(b, 5));
    s.started(b, 5);
    assert(s.needsCheckpoint(null, 5));
}

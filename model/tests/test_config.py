from dataclasses import replace

from lucidcue_model.config import Config, clamp


def test_defaults():
    c = Config()
    assert (c.hr_rise, c.var_ratio, c.max_cues_per_night, c.start_level) == (0.05, 1.3, 6, 30)


def test_clamp_out_of_range():
    c = clamp(replace(Config(), earliest_cue_hours=12.0, max_cues_per_night=0, start_level=95,
                      train_reps=50, hr_rise=-1.0, var_ratio=9.0))
    assert (c.earliest_cue_hours, c.max_cues_per_night, c.start_level, c.train_reps, c.hr_rise,
            c.var_ratio) == (7.0, 1, 80, 10, 0.0, 2.0)

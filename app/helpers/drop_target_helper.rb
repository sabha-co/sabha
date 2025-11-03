module DropTargetHelper
  def drop_target_actions
    "dragenter->drop-target#dragenter dragover->drop-target#dragover drop->drop-target#drop"
  end
end

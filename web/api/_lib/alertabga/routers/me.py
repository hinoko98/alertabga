from fastapi import APIRouter, Depends

from ..deps import CurrentUser, get_current_user

router = APIRouter(tags=["cuenta"])


@router.get("/me")
def me(user: CurrentUser = Depends(get_current_user)) -> dict:
    return {"id": user.id, "role": user.role, "full_name": user.full_name}

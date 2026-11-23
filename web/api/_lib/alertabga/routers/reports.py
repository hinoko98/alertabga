from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from ..citizens import CurrentCitizen, get_current_citizen
from ..reports import client_ip, get_report_service
from ..reports.schemas import Category, ReportCreated, ReportDetail, ReportIn, ReportSummary, TrackIn
from ..reports.service import InvalidReport, NotFound, RateLimited, ReportService, Requester

router = APIRouter(tags=["reportes"])

NOT_FOUND = "Radicado o código no válido"


def _device(x_device_id: str | None) -> str | None:
    if x_device_id is None:
        return None
    return x_device_id.strip()[:100] or None


def _create(svc: ReportService, data: ReportIn, req: Requester) -> dict:
    try:
        return svc.create(data, req)
    except InvalidReport as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from e
    except RateLimited as e:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                            "Ha enviado demasiados reportes. Intente más tarde.") from e


@router.get("/categories", response_model=list[Category])
def categories(svc: ReportService = Depends(get_report_service)) -> list[dict]:
    return svc.repo.active_categories()


@router.post("/reports", response_model=ReportCreated, response_model_exclude_none=True,
             status_code=status.HTTP_201_CREATED)
def create_report(data: ReportIn, request: Request,
                  user: CurrentCitizen = Depends(get_current_citizen),
                  x_device_id: str | None = Header(default=None),
                  svc: ReportService = Depends(get_report_service)) -> dict:
    req = Requester(client_ip(request), _device(x_device_id), user.id, user.role)
    return _create(svc, data, req)


@router.post("/reports/anonymous", response_model=ReportCreated, status_code=status.HTTP_201_CREATED)
def create_anonymous(data: ReportIn, request: Request,
                     x_device_id: str | None = Header(default=None),
                     svc: ReportService = Depends(get_report_service)) -> dict:
    return _create(svc, data, Requester(client_ip(request), _device(x_device_id)))


@router.get("/reports/mine", response_model=list[ReportSummary])
def my_reports(user: CurrentCitizen = Depends(get_current_citizen),
               svc: ReportService = Depends(get_report_service)):
    return svc.mine(Requester(None, None, user.id, user.role))


@router.post("/reports/track", response_model=ReportDetail)
def track(body: TrackIn, request: Request, x_device_id: str | None = Header(default=None),
          svc: ReportService = Depends(get_report_service)):
    try:
        return svc.track(body.radicado, body.token, Requester(client_ip(request), _device(x_device_id)))
    except NotFound as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND) from e
    except RateLimited as e:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Demasiadas consultas. Intente más tarde.") from e


@router.get("/reports/{radicado}", response_model=ReportDetail)
def report_detail(radicado: str, user: CurrentCitizen = Depends(get_current_citizen),
                  svc: ReportService = Depends(get_report_service)):
    try:
        return svc.detail_for_owner(radicado, Requester(None, None, user.id, user.role))
    except NotFound as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND) from e
